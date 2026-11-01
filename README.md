# lxc-postconf

Script bash interactif de post-configuration pour conteneurs LXC et machines virtuelles sur **Proxmox VE 8.x**. Exécuté en **root** sur l'hôte Proxmox.

Fonctions principales :

- renommage, auto-login console, injection de clés SSH (hôte ou saisie)
- prompt root : nom LXC + CTID surlignés (fond ANSI selon CTID)
- réplication ZFS + HA (cluster 2 nœuds)
- sous-menu **Maintenance** : nettoyage local d'un CT, installation/activation d'`unattended-upgrades` + `needrestart` (bulk running ou un CT avec `Automatic-Reboot` à minuit), et raccourcis [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) (`clean-lxcs` / clean and update, `disk-health`)

## Prérequis

| Élément | Détail |
|--------|--------|
| Proxmox VE | Version **8.x** ou supérieure |
| Privilèges | Utilisateur **root** sur le nœud Proxmox |
| Outils | `pct`, `qm` (optionnel), `pvesr`, `ha-manager` selon le menu |
| Cluster | Option **4** (réplication + HA) : cluster **2 nœuds**, stockage ZFS avec réplication, HA activé |
| Maintenance community-scripts | `curl`, `whiptail` ; accès HTTPS vers `raw.githubusercontent.com/community-scripts/ProxmoxVE` (`disk-health` peut installer `smartmontools` / `nvme-cli`) |

## Installation

Sur l'hôte Proxmox (en root) :

```bash
curl -fsSL https://raw.githubusercontent.com/Emilien-Etadam/proxmox_superscript/main/lxc-postconf.sh -o /usr/local/bin/lxc-postconf && chmod +x /usr/local/bin/lxc-postconf
```

Puis lancer :

```bash
lxc-postconf
```

## Mise à jour

Relancer le même one-liner pour écraser `/usr/local/bin/lxc-postconf` avec la dernière version de `main` :

```bash
curl -fsSL https://raw.githubusercontent.com/Emilien-Etadam/proxmox_superscript/main/lxc-postconf.sh -o /usr/local/bin/lxc-postconf && chmod +x /usr/local/bin/lxc-postconf
```

## Usage

Le script affiche un menu en boucle jusqu'à la sortie (`0`). Une annulation au milieu d'une option ramène au menu (ne quitte pas le script). Les menus (principal, Maintenance, source de la clé SSH) ont un titre, les actions groupées, puis la sortie séparée. Sur un terminal, le titre est en gras et la touche en cyan ; ces couleurs sont absentes si `NO_COLOR` est défini, si `TERM` vaut `dumb`, ou si la sortie n'est pas un terminal.

### Menu principal

```text
Post-config Proxmox

  1  Renommer un conteneur
  2  Auto-login root sur console tty
  3  Injecter une clé SSH
  4  Réplication + HA (tous les CT/VM)
  5  Personnaliser le prompt root (un CT ou tous running)
  6  Maintenance...

  0  Quitter
```

### Sous-menu Maintenance

```text
Maintenance

  1  Nettoyer un conteneur (espace disque)
  2  Clean and update tous les LXC (community-scripts)
  3  Santé disques SMART (community-scripts)
  4  unattended-upgrades + needrestart (LXC Debian running)
  5  Automatic-Reboot unattended (un CT, 00:00)

  0  Retour
```

### Source de la clé SSH

Option **3**, une fois le CTID choisi :

```text
Source de la clé

  1  Depuis authorized_keys hôte
  2  Saisie manuelle

  0  Annuler
```

### Exemple de session (option 1 — renommage)

Le CTID est celui déjà affiché dans l'interface Proxmox. Le script ne reliste pas les conteneurs.

```text
  Choix : 1

Conteneur

  Saisissez le CTID affiché dans Proxmox.

  CTID : 100
Nom actuel : app-web
Nouveau nom : app-web-prod
[OK] Conteneur renommé : app-web-prod
```

### Options du menu principal

| Choix | Fonction | Description |
|-------|----------|-------------|
| **1** | Renommer un conteneur | Met à jour le hostname Proxmox (`pct set --hostname`) et, si le CT est démarré, le hostname dans le guest (`hostnamectl` ou `hostname`). |
| **2** | Auto-login root console | Configure `container-getty@` pour connecter automatiquement root sur la console Proxmox (TTY série du CT). |
| **3** | Injecter une clé SSH | Sous-choix : depuis `/root/.ssh/authorized_keys` de l'hôte (une ligne ou `all`), ou saisie manuelle. Déduplique les lignes déjà présentes dans le CT. |
| **4** | Réplication + HA | Pour **chaque** CT et VM : crée un job `pvesr` vers le nœud cible (défaut `pve2`, schedule `*/15`) si absent, lance une **sync initiale séquentielle**, puis enregistre la ressource dans `ha-manager` seulement si la sync a réussi (échecs listés, pas de faux `[OK]`). En cas de `No common base snapshot` : détruire le volume zombie sur la cible ou `pvesr delete <VMID>-0`, puis relancer **4**. |
| **5** | Prompt root surligné | Demande d’abord **o/n** : appliquer à **tous les LXC running du nœud local**, sinon saisie d’un **CTID**. Installe `/etc/profile.d/lxc-postconf-prompt.sh` : invite ` hostname CTID ` (nom LXC + numéro) en **texte blanc gras sur fond ANSI** (`40 + CTID % 8`), puis le cwd. **Nœud local seulement** (`pct`) : les CT d’autres nœuds du cluster sont listés en avertissement ; relancer l’option **5** sur chaque nœud. |
| **6** | Maintenance… | Ouvre le sous-menu Maintenance. |
| **0** | Quitter | Termine le script. |

Les options **1**, **2**, **3** et **5** (si réponse **n** au bulk), ainsi que Maintenance **1** et **5**, demandent le **CTID** affiché dans Proxmox (chiffres seulement, pas de tableau de tous les conteneurs). Si le conteneur est arrêté, le script propose de le démarrer. L'existence du CT est vérifiée via les configs du nœud (`/etc/pve/local/lxc/`), pas via `pct list` : un socket LXC cassé n'empêche pas de cibler un autre CT.

### Options Maintenance

| Choix | Fonction | Description |
|-------|----------|-------------|
| **1** | Nettoyer un conteneur | Nettoyage **local** d'un CT : caches paquets, journaux, temp ; prune Docker/Podman si détecté (volumes optionnels). Affiche l'usage disque avant/après. |
| **2** | Clean and update LXC | Exécute [`clean-lxcs.sh`](https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/clean-lxcs.sh) après un patch lxc-postconf (rev **skip-stopped-v2**) : les CT **non running sont ignorés** (pas de `pct start`). Nettoyage multi-CT puis `apt update`. |
| **3** | Santé disques SMART | Confirme puis exécute [`disk-health.sh`](https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/disk-health.sh) sur l'**hôte** (rapport SMART, self-test court optionnel). |
| **4** | unattended-upgrades + needrestart | Sur **tous les LXC running** du nœud (famille Debian) : installe **et active** `unattended-upgrades` + `needrestart`. **Sans** `Automatic-Reboot`. Confirmation préalable ; CT arrêtés et guests hors Debian ignorés. |
| **5** | Automatic-Reboot (un CT) | Saisie d'un **CTID** : install/activation comme **4** sur ce CT, puis `Unattended-Upgrade::Automatic-Reboot` à **00:00**. Reboot **seulement si une mise à jour l'exige** (pas un reboot quotidien forcé). |
| **0** | Retour | Revient au menu principal. |

| Option | Périmètre |
|--------|-----------|
| Maintenance **1** | Un seul CT, nettoyage **local** (Docker/Podman inclus) |
| Maintenance **2** | Multi-CT via community-scripts (clean + refresh listes apt) |
| Maintenance **3** | Disques physiques de l'**hôte** Proxmox (pas les CT) |
| Maintenance **4** | Tous les LXC **running** du nœud, famille Debian, **sans** auto-reboot |
| Maintenance **5** | Un CT (CTID), famille Debian, **avec** Automatic-Reboot 00:00 |

#### Maintenance **4** / **5** — ce qui est activé

Base commune (bulk **4** ou un CT via **5**), après confirmation :

| Élément | Action |
|--------|--------|
| Paquets | `apt-get install unattended-upgrades needrestart` |
| Périodicité apt | Écrit `/etc/apt/apt.conf.d/20auto-upgrades` (`Update-Package-Lists` + `Unattended-Upgrade` à `"1"`) + `dpkg-reconfigure` non-interactif |
| systemd (si présent) | `enable` + `start` de `apt-daily.timer`, `apt-daily-upgrade.timer`, et `unattended-upgrades.service` |
| needrestart | Hook apt du paquet + `/etc/needrestart/conf.d/lxc-postconf.conf` (`$nrconf{restart} = 'a'`, redémarrage auto des services) |

**Maintenance 5 seulement** — fichier `/etc/apt/apt.conf.d/51lxc-postconf-auto-reboot` :

```text
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "00:00";
```

Le CT redémarre **uniquement** si unattended-upgrades a posé un besoin de reboot après une maj (mécanisme Debian `reboot-required`), dans la fenêtre autour de **minuit**. Ce n'est **pas** un timer de reboot quotidien forcé.

Les entrées community-scripts (**2**–**3**) délèguent à des scripts **externes** téléchargés à la volée (confirmation + allowlist d'URL).

## Contribution

1. Forkez le dépôt.
2. Créez une branche (`git checkout -b feature/ma-modif`).
3. Committez vos changements (`git commit -am 'Description claire'`).
4. Poussez la branche (`git push origin feature/ma-modif`).
5. Ouvrez une **Pull Request** sur GitHub.

Les bugs et idées d'amélioration passent par les **Issues** du dépôt.

## Licence

Ce projet est sous licence **MIT**. Le texte complet figure dans l'en-tête de `lxc-postconf.sh` (`SPDX-License-Identifier: MIT`).
