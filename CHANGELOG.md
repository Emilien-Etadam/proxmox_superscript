# Changelog

Toutes les modifications notables de ce projet sont documentées dans ce fichier.

Le format s'inspire de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
et ce projet respecte [Semantic Versioning](https://semver.org/lang/fr/).

## [Unreleased]

### Added

- Prompt bash root dans le CT via `/etc/profile.d/lxc-postconf-prompt.sh`, couleur ANSI dérivée du CTID.
- Nettoyage d'espace disque local d'un CT (caches, journaux, temp) avec prune Docker/Podman si détecté.
- Raccourcis community-scripts : `update-lxcs`, `clean-lxcs`, `disk-health` (confirmation + allowlist d'URL).
- Sous-menu **Maintenance** regroupant nettoyage local + raccourcis community-scripts.
- Injection SSH : déduplication des lignes déjà présentes dans `authorized_keys` du CT.

### Changed

- Menu principal allégé et renuméroté : SSH unique (**3**), réplication+HA (**4**), prompt (**5**), Maintenance (**6**).
- Options SSH hôte / manuelle fusionnées en une seule entrée avec sous-choix.
- README : section Mise à jour, documentation du sous-menu Maintenance.

### Deprecated

### Removed

- Entrées menu séparées « clé SSH hôte » et « clé SSH manuelle » (remplacées par l'option **3** unifiée).
- Entrées menu plates 7–10 pour la maintenance (déplacées dans le sous-menu **6**).

### Fixed

- Une annulation / erreur d'option ne quitte plus le script sous `set -e` (menu principal et Maintenance).

### Security

<!-- Exemple de release publiée :
## [1.0.0] - 2026-05-20

### Added

- Première version publique de lxc-postconf.sh

[Unreleased]: https://github.com/Emilien-Etadam/proxmox_superscript/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Emilien-Etadam/proxmox_superscript/releases/tag/v1.0.0
-->
