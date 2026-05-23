# lxc-postconf

Script bash interactif de post-configuration pour conteneurs LXC et machines virtuelles sur **Proxmox VE 8.x**. Exécuté en root sur l'hôte Proxmox, il simplifie les tâches courantes après création d'un CT : renommage, auto-login console, injection de clés SSH, et configuration groupée réplication ZFS + HA sur un cluster à deux nœuds.

## Prérequis

| Élément | Détail |
|--------|--------|
| Proxmox VE | Version **8.x** ou supérieure |
| Privilèges | Utilisateur **root** sur le nœud Proxmox |
| Outils | `pct`, `qm` (optionnel), `pvesr`, `ha-manager` selon le menu |
| Cluster | Option **5** (réplication + HA) : cluster **2 nœuds**, stockage ZFS avec réplication, HA activé |

## Installation

One-liner depuis ce dépôt (à adapter si le dépôt est renommé ou forké) :

```bash
curl -fsSL https://raw.githubusercontent.com/Emilien-Etadam/proxmox_superscript/main/lxc-postconf.sh -o /usr/local/bin/lxc-postconf && chmod +x /usr/local/bin/lxc-postconf
```

Puis lancer :

```bash
lxc-postconf
```

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
| **0** | Quitter | Termine le script. |

Les options **1** à **4** et **6** demandent d'abord un **CTID** ; si le conteneur est arrêté, le script propose de le démarrer.

## Contribution

1. Forkez le dépôt.
2. Créez une branche (`git checkout -b feature/ma-modif`).
3. Committez vos changements (`git commit -am 'Description claire'`).
4. Poussez la branche (`git push origin feature/ma-modif`).
5. Ouvrez une **Pull Request** sur GitHub.

Les bugs et idées d'amélioration passent par les **Issues** du dépôt.

## Licence

Ce projet est sous licence **MIT**. Le texte complet figure dans l'en-tête de `lxc-postconf.sh` (`SPDX-License-Identifier: MIT`).
