# lxc-postconf

Script bash interactif de post-configuration pour conteneurs LXC et machines virtuelles sur **Proxmox VE 8.x**. Exécuté en **root** sur l'hôte Proxmox.

Fonctions principales :

- renommage, auto-login console, injection de clés SSH
- prompt root coloré selon le CTID
- nettoyage d'espace disque d'un CT (avec Docker/Podman si présent)
- réplication ZFS + HA (cluster 2 nœuds)
- raccourcis vers [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) : `update-lxcs`, `clean-lxcs`, `disk-health`

## Prérequis

| Élément | Détail |
|--------|--------|
| Proxmox VE | Version **8.x** ou supérieure |
| Privilèges | Utilisateur **root** sur le nœud Proxmox |
| Outils | `pct`, `qm` (optionnel), `pvesr`, `ha-manager` selon le menu |
| Cluster | Option **5** (réplication + HA) : cluster **2 nœuds**, stockage ZFS avec réplication, HA activé |
| Options **8**–**10** | `curl`, `whiptail` ; accès HTTPS vers `raw.githubusercontent.com/community-scripts/ProxmoxVE` (`disk-health` peut installer `smartmontools` / `nvme-cli`) |

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

Vérifier la présence des options **8**–**10** au menu après mise à jour.

## Usage

Le script affiche un menu en boucle jusqu'à la sortie (`0`).

### Exemple de session (option 1 — renommage)

```text
=== Post-config Proxmox ===
1) Renommer un conteneur
2) Auto-login root sur console tty
3) Injecter une clé SSH (depuis authorized_keys hôte)
4) Injecter une clé SSH (saisie manuelle)
5) Réplication + HA (tous les CT/VM)
6) Personnaliser le prompt root (couleur selon CTID)
7) Nettoyer un conteneur (espace disque)
8) Mettre à jour tous les LXC (community-scripts)
9) Nettoyer tous les LXC (community-scripts)
10) Santé disques SMART (community-scripts)
0) Quitter

Choix : 1
Conteneurs disponibles :
VMID       Status     Lock         Name
100        running                 app-web

CTID du conteneur : 100
Nom actuel : app-web
Nouveau nom : app-web-prod
[OK] Conteneur renommé : app-web-prod
```

### Options du menu

| Choix | Fonction | Description |
|-------|----------|-------------|
| **1** | Renommer un conteneur | Met à jour le hostname Proxmox (`pct set --hostname`) et, si le CT est démarré, le hostname dans le guest (`hostnamectl` ou `hostname`). |
| **2** | Auto-login root console | Configure `container-getty@` pour connecter automatiquement root sur la console Proxmox (TTY série du CT). |
| **3** | Clé SSH depuis l'hôte | Liste les lignes de `/root/.ssh/authorized_keys` sur l'hôte ; injecte une ligne, ou toutes (`all`), dans le CT. |
| **4** | Clé SSH manuelle | Demande de coller une clé publique SSH et l'ajoute à `/root/.ssh/authorized_keys` du CT. |
| **5** | Réplication + HA | Pour **chaque** CT et VM : crée un job `pvesr` vers le nœud cible (défaut `pve2`, schedule `*/15`) si absent, lance une sync initiale, puis enregistre la ressource dans `ha-manager` si absente. |
| **6** | Prompt root coloré | Installe `/etc/profile.d/lxc-postconf-prompt.sh` dans le CT : invite `===[ user@host cwd ]===` avec une couleur **ANSI stable** calculée à partir du **CTID** (`31 + CTID % 8`). Visible après une nouvelle session shell (console, SSH, `pct enter`). |
| **7** | Nettoyer un conteneur | Libère de l'espace disque : caches paquets (`apt`/`apk`/`dnf`/`yum`), journaux (`journalctl` + fichiers rotatés), `/tmp` et `/var/tmp`. Si **Docker** ou **Podman** est présent, prune conteneurs/images/réseaux/build cache (volumes optionnels sur confirmation). Affiche l'usage disque avant/après. |
| **8** | Update tous les LXC | Confirme puis exécute [`update-lxcs.sh`](https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/update-lxcs.sh) (UI `whiptail` : exclusions, skip CT arrêtés, `apt`/`apk`/`dnf`/…). |
| **9** | Clean tous les LXC | Confirme puis exécute [`clean-lxcs.sh`](https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/clean-lxcs.sh) (UI `whiptail` : logs/cache, `autoremove`, `apt update` sur les CT retenus). |
| **10** | Santé disques SMART | Confirme puis exécute [`disk-health.sh`](https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/disk-health.sh) sur l'**hôte** : rapport SMART des disques physiques, self-test court optionnel (`whiptail`). |
| **0** | Quitter | Termine le script. |

Les options **1** à **4**, **6** et **7** demandent d'abord un **CTID** ; si le conteneur est arrêté, le script propose de le démarrer.

Les options **8** à **10** délèguent à des scripts **externes** (téléchargés à la volée depuis community-scripts). Différences utiles :

| Option | Périmètre |
|--------|-----------|
| **7** | Un seul CT, nettoyage **local** (Docker/Podman inclus) |
| **9** | Multi-CT via community-scripts + UI whiptail |
| **10** | Disques physiques de l'**hôte** Proxmox (pas les CT) |

## Contribution

1. Forkez le dépôt.
2. Créez une branche (`git checkout -b feature/ma-modif`).
3. Committez vos changements (`git commit -am 'Description claire'`).
4. Poussez la branche (`git push origin feature/ma-modif`).
5. Ouvrez une **Pull Request** sur GitHub.

Les bugs et idées d'amélioration passent par les **Issues** du dépôt.

## Licence

Ce projet est sous licence **MIT**. Le texte complet figure dans l'en-tête de `lxc-postconf.sh` (`SPDX-License-Identifier: MIT`).
