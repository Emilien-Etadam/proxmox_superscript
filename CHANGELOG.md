# Changelog

Toutes les modifications notables de ce projet sont documentées dans ce fichier.

Le format s'inspire de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
et ce projet respecte [Semantic Versioning](https://semver.org/lang/fr/).

## [Unreleased]

### Added

- Option menu **6** : prompt bash root dans le CT via `/etc/profile.d/lxc-postconf-prompt.sh`, couleur ANSI dérivée du CTID.
- Option menu **7** : nettoyage d'espace disque dans un CT (caches paquets, journaux, temp) avec prune Docker/Podman si détecté.
- Options menu **8** / **9** / **10** : raccourcis vers `update-lxcs.sh`, `clean-lxcs.sh` et `disk-health.sh` (community-scripts/ProxmoxVE), avec confirmation et contrôle d'URL avant exécution distante.

### Changed

- README : section **Mise à jour**, intro clarifiée, tableau de comparaison des options 7 / 9 / 10.

### Deprecated

### Removed

### Fixed

### Security

<!-- Exemple de release publiée :
## [1.0.0] - 2026-05-20

### Added

- Première version publique de lxc-postconf.sh

[Unreleased]: https://github.com/Emilien-Etadam/proxmox_superscript/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Emilien-Etadam/proxmox_superscript/releases/tag/v1.0.0
-->
