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
#
# Licence: MIT — Copyright (c) Emilien-Etadam
# SPDX-License-Identifier: MIT

set -euo pipefail

# Identifiant du conteneur LXC sélectionné (partagé entre les options du menu).
CTID=""

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
    echo "3) Injecter une clé SSH (depuis authorized_keys hôte)"
    echo "4) Injecter une clé SSH (saisie manuelle)"
    echo "5) Réplication + HA (tous les CT/VM)"
    echo "0) Quitter"
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

# Injecte une ou plusieurs clés SSH depuis /root/.ssh/authorized_keys de l'hôte.
#
# Paramètres : aucun (sélection CT et ligne(s) sur stdin).
# Effets de bord : ajoute des entrées dans /root/.ssh/authorized_keys du conteneur.
# Retour : 0 si succès, 1 si fichier hôte absent ou sélection vide.
inject_ssh_from_host() {
    select_ct || return 1
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
        keys=$(sed -n "${selection}p" "$host_keys")
    fi

    if [[ -z "$keys" ]]; then
        echo "ERREUR : sélection vide."
        return 1
    fi

    pct exec "$CTID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root bash -c "
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        cat >> /root/.ssh/authorized_keys <<'SSHEOF'
$keys
SSHEOF
        chmod 600 /root/.ssh/authorized_keys
    "
    echo "[OK] Clé(s) injectée(s)."
}

# Injecte une clé SSH publique saisie manuellement dans le conteneur.
#
# Paramètres : aucun (sélection CT via select_ct, clé sur stdin).
# Effets de bord : ajoute une entrée dans /root/.ssh/authorized_keys du conteneur.
# Retour : 0 si succès, 1 si clé vide.
inject_ssh_manual() {
    select_ct || return 1
    local pubkey
    read -rp "Coller la clé publique SSH : " pubkey
    if [[ -z "$pubkey" ]]; then
        echo "ERREUR : clé vide."
        return 1
    fi
    pct exec "$CTID" -- env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root bash -c "
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        cat >> /root/.ssh/authorized_keys <<'SSHEOF'
$pubkey
SSHEOF
        chmod 600 /root/.ssh/authorized_keys
    "
    echo "[OK] Clé injectée."
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

# --- Boucle principale ---
while true; do
    show_menu
    choice=""
    read -rp "Choix : " choice
    case "$choice" in
        1) rename_ct ;;
        2) setup_autologin ;;
        3) inject_ssh_from_host ;;
        4) inject_ssh_manual ;;
        5) setup_replication_ha ;;
        0) exit 0 ;;
        *) echo "Choix invalide." ;;
    esac
done
