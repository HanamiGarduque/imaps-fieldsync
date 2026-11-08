# Changelog

## 1.0.0

### Added
- A 35-stop English/Tagalog Guide with first-launch and manual replay support.
- Confirmed overwrite-all handling for sync conflicts.

### Fixed
- Guide highlights on small displays and the pinned Guide-page header.
- False sync conflicts and synchronization revision tracking.

### Changed
- Updated the bundled policy notices and regression checks.

### Security
- Production releases require a pinned, external production signing key;
  debug-signing fallback is removed. This is a new signer, not a recovered key.
