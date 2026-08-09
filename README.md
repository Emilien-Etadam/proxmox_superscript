# lxc-postconf

Script bash interactif de post-configuration pour conteneurs LXC et machines virtuelles sur **Proxmox VE 8.x**. Exécuté en **root** sur l'hôte Proxmox.

Fonctions principales :

- renommage, auto-login console, injection de clés SSH (hôte ou saisie)
- prompt root coloré selon le CTID
- réplication ZFS + HA (cluster 2 nœuds)
- sous-menu **Maintenance** : nettoyage local d'un CT, et raccourcis [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) (`clean-lxcs` / clean and update, `disk-health`)

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

Le script affiche un menu en boucle jusqu'à la sortie (`0`). Une annulation au milieu d'une option ramène au menu (ne quitte pas le script).

### Menu principal

```text
=== Post-config Proxmox ===
1) Renommer un conteneur
2) Auto-login root sur console tty
3) Injecter une clé SSH
4) Réplication + HA (tous les CT/VM)
5) Personnaliser le prompt root (couleur selon CTID)
6) Maintenance...
0) Quitter
```

### Sous-menu Maintenance

```text
=== Maintenance ===
1) Nettoyer un conteneur (espace disque)
2) Clean and update tous les LXC (community-scripts)
3) Santé disques SMART (community-scripts)
0) Retour
```

### Exemple de session (option 1 — renommage)

```text
Choix : 1
Conteneurs disponibles :
VMID       Status     Lock         Name
100        running                 app-web

CTID du conteneur : 100
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
| **4** | Réplication + HA | Pour **chaque** CT et VM : crée un job `pvesr` vers le nœud cible (défaut `pve2`, schedule `*/15`) si absent, lance une sync initiale, puis enregistre la ressource dans `ha-manager` si absente. |
| **5** | Prompt root coloré | Installe `/etc/profile.d/lxc-postconf-prompt.sh` dans le CT : invite `===[ user@host cwd ]===` avec une couleur **ANSI stable** calculée à partir du **CTID** (`31 + CTID % 8`). |
| **6** | Maintenance… | Ouvre le sous-menu Maintenance. |
| **0** | Quitter | Termine le script. |

Les options **1**, **2**, **3** et **5** demandent d'abord un **CTID** ; si le conteneur est arrêté, le script propose de le démarrer.

### Options Maintenance

| Choix | Fonction | Description |
|-------|----------|-------------|
| **1** | Nettoyer un conteneur | Nettoyage **local** d'un CT : caches paquets, journaux, temp ; prune Docker/Podman si détecté (volumes optionnels). Affiche l'usage disque avant/après. |
| **2** | Clean and update LXC | Exécute [`clean-lxcs.sh`](https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/clean-lxcs.sh) après un patch lxc-postconf (rev **skip-stopped-v2**) : les CT **non running sont ignorés** (pas de `pct start`). Nettoyage multi-CT puis `apt update`. |
| **3** | Santé disques SMART | Confirme puis exécute [`disk-health.sh`](https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/disk-health.sh) sur l'**hôte** (rapport SMART, self-test court optionnel). |
| **0** | Retour | Revient au menu principal. |

| Option | Périmètre |
|--------|-----------|
| Maintenance **1** | Un seul CT, nettoyage **local** (Docker/Podman inclus) |
| Maintenance **2** | Multi-CT via community-scripts (clean + refresh listes apt) |
| Maintenance **3** | Disques physiques de l'**hôte** Proxmox (pas les CT) |

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
