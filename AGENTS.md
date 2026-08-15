# AGENTS.md

## Cursor Cloud specific instructions

Ce dépôt est **un unique script Bash** : `lxc-postconf.sh`. Il n'y a aucun gestionnaire de
paquets, aucune étape de build, aucune suite de tests automatisés, et aucun service à démarrer.

### Contexte produit

`lxc-postconf.sh` est un utilitaire interactif de post-configuration pour **Proxmox VE 8.x**,
prévu pour être exécuté **en root sur un hôte Proxmox**. Il dépend d'outils système fournis
uniquement par Proxmox : `pct`, `qm`, `pvesr`, `ha-manager`. Ces binaires **n'existent pas**
dans un environnement de dev standard : les options du menu qui les appellent échoueront ici.

### Lint (ce qui tourne réellement dans cet environnement)

- Vérification syntaxe : `bash -n lxc-postconf.sh`
- Analyse statique : `shellcheck lxc-postconf.sh` (le dépôt est actuellement clean).
  `shellcheck` est un outil système (`apt-get install -y shellcheck` si absent), non déclaré
  dans le dépôt.

### Tests / Build

Aucun. Pas de suite de tests ni d'étape de build.

### Exécuter / démontrer sans hôte Proxmox

Le script fonctionne réellement de bout en bout uniquement sur un hôte Proxmox. Pour le tester
hors Proxmox, on peut fournir des commandes `pct`/`qm` **simulées** en tête de `PATH` (sans
modifier le code du dépôt), par exemple :

```bash
printf '9\n1\n100\napp-web-prod\n0\n' | PATH="/tmp/mockbin:$PATH" bash lxc-postconf.sh
```

où `/tmp/mockbin/pct` simule `pct list|status|config|set|exec`. Cela exerce la boucle du menu,
la gestion d'un choix invalide, et le flux de renommage (`select_ct` + `rename_ct`).

Le script lit toutes ses entrées sur stdin de façon interactive (`read -rp`) : pour l'automatiser,
piper les réponses ligne par ligne dans l'ordre du menu.
