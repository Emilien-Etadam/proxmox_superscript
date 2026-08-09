#!/usr/bin/env bash
#
# lxc-postconf — Post-configuration interactive LXC/VM pour Proxmox VE 8.x
#
# Usage:
#   lxc-postconf.sh
#   # ou, après installation :
#   /usr/local/bin/lxc-postconf
#
# Prérequis:
#   - Proxmox VE 8.x, exécution en root sur l'hôte
#   - Outils : pct, qm, pvesr, ha-manager (selon les options du menu)
#   - Option 5 (réplication + HA) : cluster 2 nœuds, ZFS, réplication configurée
#   - Sous-menu Maintenance (community-scripts) : curl, whiptail ; téléchargent
#     et exécutent du code distant depuis github.com/community-scripts/ProxmoxVE
#     (disk-health peut aussi installer smartmontools / nvme-cli via apt)
#
# Licence: MIT — Copyright (c) Emilien-Etadam
# SPDX-License-Identifier: MIT

set -euo pipefail

# Identifiant du conteneur LXC sélectionné (partagé entre les options du menu).
CTID=""

# Scripts community-scripts/ProxmoxVE (exécutés sur l'hôte via curl | bash).
readonly COMMUNITY_SCRIPTS_BASE_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve"
readonly COMMUNITY_CLEAN_LXCS_URL="${COMMUNITY_SCRIPTS_BASE_URL}/clean-lxcs.sh"
readonly COMMUNITY_DISK_HEALTH_URL="${COMMUNITY_SCRIPTS_BASE_URL}/disk-health.sh"

# Affiche la liste des conteneurs, demande un CTID et démarre le CT si nécessaire.
#
# Paramètres : aucun (lit CTID sur stdin).
# Effets de bord : met à jour la variable globale CTID ; peut démarrer le conteneur (pct start).
# Retour : 0 si le conteneur est utilisable, 1 sinon.
select_ct() {
    echo "Conteneurs disponibles :"
    pct list
    echo ""
    read -rp "CTID du conteneur : " CTID

    local status
    status=$(pct status "$CTID" 2>/dev/null | awk '{print $2}') || {
        echo "ERREUR : conteneur $CTID introuvable."
        return 1
    }
    if [[ "$status" != "running" ]]; then
        local start
        read -rp "Le conteneur $CTID est arrêté. Démarrer ? (o/n) : " start
        [[ "$start" == "o" ]] && pct start "$CTID" && sleep 3 || return 1
    fi
}

# Affiche le menu principal sur stdout.
#
# Paramètres : aucun.
# Effets de bord : aucun.
show_menu() {
    echo ""
    echo "=== Post-config Proxmox ==="
    echo "1) Renommer un conteneur"
    echo "2) Auto-login root sur console tty"
    echo "3) Injecter une clé SSH"
    echo "4) Réplication + HA (tous les CT/VM)"
    echo "5) Personnaliser le prompt root (couleur selon CTID)"
    echo "6) Maintenance..."
    echo "0) Quitter"
    echo ""
}

# Affiche le sous-menu Maintenance sur stdout.
#
# Paramètres : aucun.
# Effets de bord : aucun.
show_maintenance_menu() {
    echo ""
    echo "=== Maintenance ==="
    echo "1) Nettoyer un conteneur (espace disque)"
    echo "2) Clean and update tous les LXC (community-scripts)"
    echo "3) Santé disques SMART (community-scripts)"
    echo "0) Retour"
    echo ""
}

# Exécute une commande bash dans le conteneur CTID via pct exec.
#
# Paramètres : $1 — commande bash à exécuter (chaîne passée à bash -c).
# Effets de bord : modifie l'état du conteneur selon la commande fournie.
run_in_ct() {
    pct exec "$CTID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=xterm bash -c "$1"
}

# Renomme le hostname Proxmox et, si le CT tourne, le hostname OS du conteneur.
#
# Paramètres : aucun (sélection CT via select_ct, nouveau nom sur stdin).
# Effets de bord : pct set --hostname ; hostnamectl/hostname dans le CT.
# Retour : 0 si succès, 1 si annulation ou erreur.
rename_ct() {
    select_ct || return 1
    local current_name
    current_name=$(pct config "$CTID" | grep '^hostname:' | awk '{print $2}')
    echo "Nom actuel : $current_name"
    local new_name
    read -rp "Nouveau nom : " new_name
    if [[ -z "$new_name" ]]; then
        echo "ERREUR : nom vide."
        return 1
    fi
    pct set "$CTID" --hostname "$new_name"
    if [[ "$(pct status "$CTID" | awk '{print $2}')" == "running" ]]; then
        run_in_ct "hostnamectl set-hostname '$new_name' 2>/dev/null || hostname '$new_name'"
    fi
    echo "[OK] Conteneur renommé : $new_name"
}

# Active l'auto-login root sur la console série du conteneur (systemd getty).
#
# Paramètres : aucun (sélection CT via select_ct).
# Effets de bord : crée autologin.conf, daemon-reload, redémarre container-getty@1.
setup_autologin() {
    select_ct || return 1
    echo "[*] Configuration auto-login root console..."
    # shellcheck disable=SC2016
    run_in_ct '
        mkdir -p /etc/systemd/system/container-getty@.service.d
        cat > /etc/systemd/system/container-getty@.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
        systemctl daemon-reload
        systemctl restart container-getty@1
    '
    echo "[OK] Auto-login activé."
}

# Ajoute des clés SSH dans /root/.ssh/authorized_keys du CT (déduplication ligne à ligne).
#
# Paramètres : $1 — bloc de clés publiques (une ou plusieurs lignes).
# Effets de bord : crée ~/.ssh si besoin ; n'ajoute que les lignes absentes.
# Retour : 0 si au moins une clé ajoutée ou déjà présente, 1 si bloc vide.
append_ssh_keys_to_ct() {
    local keys="$1"
    if [[ -z "$keys" ]]; then
        echo "ERREUR : clé vide."
        return 1
    fi

    pct exec "$CTID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root bash -c "
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        added=0
        skipped=0
        while IFS= read -r line || [ -n \"\$line\" ]; do
            [ -z \"\$line\" ] && continue
            case \"\$line\" in
                \#*) continue ;;
            esac
            if grep -qxF \"\$line\" /root/.ssh/authorized_keys 2>/dev/null; then
                skipped=\$((skipped + 1))
            else
                printf '%s\n' \"\$line\" >> /root/.ssh/authorized_keys
                added=\$((added + 1))
            fi
        done <<'SSHEOF'
$keys
SSHEOF
        echo \"[OK] Clé(s) : \$added ajoutée(s), \$skipped déjà présente(s).\"
    "
}

# Injecte une clé SSH dans le CT : depuis l'hôte ou saisie manuelle.
#
# Paramètres : aucun (sélection CT + source sur stdin).
# Effets de bord : modifie /root/.ssh/authorized_keys du conteneur.
# Retour : 0 si succès, 1 si annulation / erreur.
inject_ssh() {
    select_ct || return 1

    echo "Source de la clé :"
    echo "1) Depuis authorized_keys hôte"
    echo "2) Saisie manuelle"
    echo "0) Annuler"
    local source
    read -rp "Choix : " source

    case "$source" in
        1)
            local host_keys="/root/.ssh/authorized_keys"
            if [[ ! -f "$host_keys" ]]; then
                echo "ERREUR : $host_keys absent sur l'hôte."
                return 1
            fi
            echo "Clés disponibles sur l'hôte :"
            nl -ba "$host_keys"
            echo ""
            local selection
            read -rp "Numéro de la ligne à injecter (ou 'all') : " selection
            local keys
            if [[ "$selection" == "all" ]]; then
                keys=$(cat "$host_keys")
            else
                if [[ ! "$selection" =~ ^[0-9]+$ ]]; then
                    echo "ERREUR : numéro de ligne invalide."
                    return 1
                fi
                keys=$(sed -n "${selection}p" "$host_keys")
            fi
            append_ssh_keys_to_ct "$keys"
            ;;
        2)
            local pubkey
            read -rp "Coller la clé publique SSH : " pubkey
            append_ssh_keys_to_ct "$pubkey"
            ;;
        0)
            echo "[!] Annulé."
            return 1
            ;;
        *)
            echo "Choix invalide."
            return 1
            ;;
    esac
}

# Installe un PS1 bash root dont la couleur ANSI dépend du CTID (stable par conteneur).
#
# Paramètres : aucun (sélection CT via select_ct).
# Effets de bord : écrit /etc/profile.d/lxc-postconf-prompt.sh ; retire un ancien bloc .bashrc le cas échéant.
setup_custom_ps1() {
    select_ct || return 1
    local color=$(( 31 + (CTID % 8) ))
    echo "[*] Configuration du prompt root (CTID=$CTID, couleur ANSI $color)..."

    pct exec "$CTID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root bash -c "
        install -d -m 755 /etc/profile.d
        cat > /etc/profile.d/lxc-postconf-prompt.sh <<'PROMPT_EOF'
# lxc-postconf: PS1 personnalisé (couleur dérivée du CTID, CTID=${CTID})
if [ -n \"\${BASH_VERSION:-}\" ]; then
  PS1=\"\\n\\[\\e[1;${color}m\\]===[ \\u@\\h \\w ]===\\[\\e[0m\\]\\n# \"
  export PS1
fi
PROMPT_EOF
        chmod 644 /etc/profile.d/lxc-postconf-prompt.sh
        if [ -f /root/.bashrc ] && grep -qF 'lxc-postconf: PS1 personnalisé' /root/.bashrc 2>/dev/null; then
            sed -i '/# lxc-postconf: PS1 personnalisé/,/^PS1=/d' /root/.bashrc
        fi
    "
    echo "[OK] Prompt installé (/etc/profile.d/lxc-postconf-prompt.sh). Ouvrez une nouvelle session shell."
}

# Libère de l'espace disque dans un conteneur : caches paquets, journaux, temp ;
# si Docker (ou Podman) est présent, prune les ressources inutilisées.
#
# Paramètres : aucun (sélection CT via select_ct ; confirmation stdin pour volumes Docker).
# Effets de bord : supprime caches/journaux/temp dans le CT ; éventuellement prune Docker/Podman.
# Retour : 0 si succès, 1 si annulation ou CT inaccessible.
cleanup_ct() {
    select_ct || return 1

    local before
    before=$(run_in_ct "df -h / | awk 'NR==2 {print \$3\" utilisés / \"\$2\" (\"\$5\" )\"}'" 2>/dev/null || echo "indisponible")
    echo "[*] Espace / avant nettoyage : $before"

    local has_docker=0
    if run_in_ct "command -v docker >/dev/null 2>&1"; then
        has_docker=1
        echo "[*] Docker détecté dans le CT."
    elif run_in_ct "command -v podman >/dev/null 2>&1"; then
        has_docker=1
        echo "[*] Podman détecté dans le CT (nettoyage équivalent)."
    else
        echo "[*] Pas de Docker/Podman : nettoyage système uniquement."
    fi

    local prune_volumes=0
    if [[ "$has_docker" -eq 1 ]]; then
        local confirm_vol
        read -rp "Supprimer aussi les volumes Docker/Podman inutilisés ? (o/n) : " confirm_vol
        [[ "$confirm_vol" == "o" ]] && prune_volumes=1
    fi

    local confirm
    read -rp "Lancer le nettoyage sur CT $CTID ? (o/n) : " confirm
    if [[ "$confirm" != "o" ]]; then
        echo "[!] Annulé."
        return 1
    fi

    echo "[*] Nettoyage en cours..."
    # PRUNE_VOLUMES est injecté depuis l'hôte ; le reste du script est auto-contenu.
    run_in_ct "
        PRUNE_VOLUMES=${prune_volumes}

        echo '--- Caches paquets ---'
        if command -v apt-get >/dev/null 2>&1; then
            apt-get autoremove -y 2>/dev/null || true
            apt-get clean 2>/dev/null || true
            rm -rf /var/lib/apt/lists/* 2>/dev/null || true
        elif command -v apk >/dev/null 2>&1; then
            apk cache clean 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf clean all 2>/dev/null || true
        elif command -v yum >/dev/null 2>&1; then
            yum clean all 2>/dev/null || true
        fi

        echo '--- Journaux ---'
        if command -v journalctl >/dev/null 2>&1; then
            journalctl --vacuum-time=7d 2>/dev/null || true
            journalctl --vacuum-size=100M 2>/dev/null || true
        fi
        find /var/log -type f \( -name '*.gz' -o -name '*.old' -o -name '*.[0-9]' -o -name '*.[0-9].gz' \) -delete 2>/dev/null || true
        find /var/log -type f -name '*.log' -exec truncate -s 0 {} + 2>/dev/null || true

        echo '--- Fichiers temporaires ---'
        rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
        if command -v apt-get >/dev/null 2>&1; then
            rm -rf /var/cache/apt/archives/* /var/cache/apt/archives/partial/* 2>/dev/null || true
        fi

        if command -v docker >/dev/null 2>&1; then
            echo '--- Docker ---'
            docker container prune -f 2>/dev/null || true
            docker image prune -af 2>/dev/null || true
            docker network prune -f 2>/dev/null || true
            docker builder prune -af 2>/dev/null || true
            if [ \"\$PRUNE_VOLUMES\" = \"1\" ]; then
                docker volume prune -f 2>/dev/null || true
            fi
            docker system df 2>/dev/null || true
        elif command -v podman >/dev/null 2>&1; then
            echo '--- Podman ---'
            podman container prune -f 2>/dev/null || true
            podman image prune -af 2>/dev/null || true
            podman network prune -f 2>/dev/null || true
            if [ \"\$PRUNE_VOLUMES\" = \"1\" ]; then
                podman volume prune -f 2>/dev/null || true
            fi
            podman system df 2>/dev/null || true
        fi

        sync
        echo '--- Terminé ---'
    "

    local after
    after=$(run_in_ct "df -h / | awk 'NR==2 {print \$3\" utilisés / \"\$2\" (\"\$5\" )\"}'" 2>/dev/null || echo "indisponible")
    echo "[OK] Nettoyage terminé. Espace / avant : $before | après : $after"
}

# Télécharge et exécute un script community-scripts/ProxmoxVE sur l'hôte.
#
# Paramètres : $1 — libellé court ; $2 — URL HTTPS du script raw.
# Effets de bord : exécute du code distant (curl | bash) ; UI whiptail du script distant.
# Retour : 0 après exécution ou annulation gérée ; 1 si prérequis / confirmation refusée.
run_community_script() {
    local label="$1"
    local url="$2"

    if [[ -z "$label" || -z "$url" ]]; then
        echo "ERREUR : libellé ou URL manquant pour le script community."
        return 1
    fi
    if [[ "$url" != https://raw.githubusercontent.com/community-scripts/ProxmoxVE/* ]]; then
        echo "ERREUR : URL community-scripts non autorisée."
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "ERREUR : curl est requis pour télécharger $label."
        return 1
    fi
    if ! command -v whiptail >/dev/null 2>&1; then
        echo "ERREUR : whiptail est requis par $label (paquet debconf-i18n / whiptail)."
        return 1
    fi

    echo "[!] $label télécharge et exécute du code distant :"
    echo "    $url"
    echo "[!] Vérifiez la source avant de continuer (github.com/community-scripts/ProxmoxVE)."
    local confirm
    read -rp "Lancer $label maintenant ? (o/n) : " confirm
    if [[ "$confirm" != "o" ]]; then
        echo "[!] Annulé."
        return 1
    fi

    echo "[*] Téléchargement et exécution de $label..."
    # Le script distant a son propre set -e / whiptail ; une annulation ne doit pas tuer le menu.
    local script_body
    if ! script_body=$(curl -fsSL --proto '=https' --tlsv1.2 "$url"); then
        echo "ERREUR : échec du téléchargement de $url"
        return 1
    fi
    if [[ -z "$script_body" ]]; then
        echo "ERREUR : script distant vide ($url)."
        return 1
    fi

    local rc=0
    bash -c "$script_body" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        echo "[OK] $label terminé."
    else
        echo "[!] $label s'est arrêté (code $rc)."
        if [[ "$rc" -eq 255 ]]; then
            echo "[!] Cause fréquente : un CT n'était pas running (pct exec a échoué)."
            echo "[!] Astuce : démarrez le CT (pct start CTID), ou cochez-le pour l'exclure dans whiptail."
        else
            echo "[!] Annulation whiptail, ou erreur dans le script distant."
        fi
    fi
    return 0
}

# Liste les CT non running (hors templates) et propose de les démarrer avant clean-lxcs.
#
# Paramètres : aucun.
# Effets de bord : peut démarrer des CT via pct start et attendre le statut running.
# Retour : 0 pour continuer vers le script distant ; 1 si annulation / échec démarrage.
ensure_lxcs_running_for_clean() {
    local stopped_ids=()
    local ctid status

    while read -r ctid; do
        [[ -z "$ctid" ]] && continue
        if pct config "$ctid" 2>/dev/null | grep -q '^template:'; then
            continue
        fi
        status=$(pct status "$ctid" 2>/dev/null | awk '{print $2}') || continue
        if [[ "$status" != "running" ]]; then
            stopped_ids+=("$ctid")
        fi
    done < <(pct list | awk 'NR>1 {print $1}')

    if [[ "${#stopped_ids[@]}" -eq 0 ]]; then
        return 0
    fi

    echo "[!] CT arrêtés détectés :"
    local id
    for id in "${stopped_ids[@]}"; do
        echo "    - $id"
    done
    echo "[!] clean-lxcs (distant) s'arrête au premier CT inaccessible (ex. « container not running »)."
    local confirm
    read -rp "Démarrer ces CT et attendre qu'ils soient ready ? (o/n) : " confirm
    if [[ "$confirm" != "o" ]]; then
        read -rp "Continuer sans pré-démarrage (risque d'échec) ? (o/n) : " confirm
        [[ "$confirm" == "o" ]] && return 0
        echo "[!] Annulé."
        return 1
    fi

    for id in "${stopped_ids[@]}"; do
        echo "[*] Démarrage CT $id..."
        if ! pct start "$id"; then
            echo "ERREUR : impossible de démarrer CT $id."
            echo "[!] Excluez-le dans whiptail, ou corrigez le conteneur, puis réessayez."
            return 1
        fi
        local waited=0
        while [[ "$(pct status "$id" 2>/dev/null | awk '{print $2}')" != "running" ]]; do
            waited=$((waited + 1))
            if [[ "$waited" -gt 60 ]]; then
                echo "ERREUR : CT $id n'est pas running après 60s."
                return 1
            fi
            sleep 1
        done
        # Marge pour l'init guest (hostname / apt disponibles via pct exec).
        sleep 3
        echo "[OK] CT $id running."
    done
    return 0
}

# Lance clean-lxcs.sh (nettoyage + apt update sur les LXC sélectionnés).
# Retour : toujours 0 (le menu principal ne doit pas s'interrompre sous set -e).
run_community_clean_and_update_lxcs() {
    if ! ensure_lxcs_running_for_clean; then
        return 0
    fi
    run_community_script "clean-and-update-lxcs" "$COMMUNITY_CLEAN_LXCS_URL" || true
}

# Lance disk-health.sh (rapport SMART hôte + self-test court optionnel).
# Retour : toujours 0 (le menu principal ne doit pas s'interrompre sous set -e).
run_community_disk_health() {
    run_community_script "disk-health" "$COMMUNITY_DISK_HEALTH_URL" || true
}

# Configure la réplication ZFS (pvesr) et le HA pour tous les CT et VM du cluster.
#
# Paramètres : aucun (nœud cible et schedule sur stdin, défauts pve2 et */15).
# Effets de bord : crée des jobs pvesr, lance pvesr run en arrière-plan, ajoute des ressources HA.
# Les CT avec bind mounts sont ignorés pour la réplication ; les échecs pvesr/HA n'interrompent pas le script.
setup_replication_ha() {
    local target_node="pve2"
    local schedule="*/15"

    local input_node
    read -rp "Noeud cible [$target_node] : " input_node
    [[ -n "$input_node" ]] && target_node="$input_node"
    local input_sched
    read -rp "Schedule réplication [$schedule] : " input_sched
    [[ -n "$input_sched" ]] && schedule="$input_sched"

    local ha_resources
    ha_resources=$(ha-manager status | awk '/^service/ {print $2}' | sort -u)
    local repl_resources
    repl_resources=$(pvesr status | awk 'NR>1 {split($1,a,"-"); print a[1]}' | sort -u)

    # Vérifie si une valeur est présente comme mot entier dans une liste (chaîne multiligne).
    #
    # Paramètres : $1 — valeur ; $2 — liste.
    # Retour : 0 si trouvé, 1 sinon.
    in_list() {
        grep -qw "$1" <<<"$2"
    }

    # Détecte un point de montage bind dans la config pct du conteneur.
    #
    # Paramètres : $1 — CTID.
    # Retour : 0 si bind mount présent, 1 sinon.
    has_bind_mount() {
        pct config "$1" 2>/dev/null | grep -qE '^mp[0-9]+:.*type=bind|^mp[0-9]+: /'
    }

    # Applique réplication et HA pour un CT ou une VM (id + type).
    #
    # Paramètres : $1 — VMID/CTID ; $2 — type (`ct` ou `vm`).
    # Effets de bord : pvesr create-local-job/run, ha-manager add (erreurs journalisées, pas de sortie set -e).
    process_id() {
        local vmid="$1"
        local type="$2"
        local fqid="${type}:${vmid}"

        if ! in_list "$vmid" "$repl_resources"; then
            if [[ "$type" == "ct" ]] && has_bind_mount "$vmid"; then
                echo "[!] SKIP réplication $fqid (bind mount détecté)"
            else
                echo "[+] Création réplication pour $fqid vers $target_node"
                if pvesr create-local-job "${vmid}-0" "$target_node" --schedule "$schedule" 2>&1; then
                    pvesr run --id "${vmid}-0" 2>&1 &
                else
                    echo "[!] ERREUR réplication $fqid"
                fi
            fi
        else
            echo "[=] Réplication déjà OK pour $fqid"
        fi

        if ! in_list "$fqid" "$ha_resources"; then
            echo "[+] Ajout HA pour $fqid"
            ha-manager add "$fqid" --state started 2>&1 || echo "[!] ERREUR HA $fqid"
        else
            echo "[=] HA déjà OK pour $fqid"
        fi
    }

    local vmid
    local ct_ids
    mapfile -t ct_ids < <(pct list | awk 'NR>1 {print $1}')
    for vmid in "${ct_ids[@]}"; do
        process_id "$vmid" "ct"
    done

    local vm_ids
    mapfile -t vm_ids < <(qm list 2>/dev/null | awk 'NR>1 {print $1}')
    for vmid in "${vm_ids[@]}"; do
        process_id "$vmid" "vm"
    done

    echo "[*] Attente fin des réplications initiales..."
    wait
    echo "[OK] Réplication + HA terminé."
}

# Boucle du sous-menu Maintenance (retour = 0).
#
# Paramètres : aucun.
# Effets de bord : appelle cleanup_ct / community-scripts selon le choix.
# Les échecs / annulations ne quittent pas le sous-menu (set -e).
maintenance_menu() {
    while true; do
        show_maintenance_menu
        local mchoice=""
        read -rp "Choix : " mchoice
        case "$mchoice" in
            1) cleanup_ct || true ;;
            2) run_community_clean_and_update_lxcs || true ;;
            3) run_community_disk_health || true ;;
            0) return 0 ;;
            *) echo "Choix invalide." ;;
        esac
    done
}

# --- Boucle principale ---
# || true : une annulation (return 1) ne doit pas tuer le menu sous set -e.
while true; do
    show_menu
    choice=""
    read -rp "Choix : " choice
    case "$choice" in
        1) rename_ct || true ;;
        2) setup_autologin || true ;;
        3) inject_ssh || true ;;
        4) setup_replication_ha || true ;;
        5) setup_custom_ps1 || true ;;
        6) maintenance_menu || true ;;
        0) exit 0 ;;
        *) echo "Choix invalide." ;;
    esac
done
