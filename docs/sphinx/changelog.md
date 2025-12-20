# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial implementation of Nix AI Models library
- Core `fetchModel` function for reproducible model fetching
- Source adapters:
  - HuggingFace Hub
  - Mock adapter for testing
- Validation framework with two-phase architecture
- Validation presets: strict, standard, minimal, none, paranoid
- Built-in validators:
  - `noPickleFiles` - Reject pickle files
  - `safetensorsOnly` - Require safetensors format
  - `maxSize` - Limit model size
  - `requiredFiles` - Ensure required files exist
  - `noSymlinks` - Reject symbolic links
  - `fileTypes` - Whitelist file extensions
  - `modelscan` - Security scanning
- HuggingFace cache structure integration
- Source factories for DRY configuration
- NixOS module (stub)
- Home Manager module (stub)
- Comprehensive Sphinx documentation

### Planned

- MLflow source adapter
- S3 source adapter
- Git LFS source adapter
- Git-Xet source adapter
- URL source adapter
- Ollama source adapter
- CLI tool (`nix-ai-models`)
- Full NixOS module implementation
- Full Home Manager module implementation
- Binary cache optimization for large models

## [0.1.0] - TBD

### Added

- First public release
- Complete source adapter implementations
- Full documentation
- Example flakes

---

## Release Notes Format

Each release includes:

- **Added** - New features
- **Changed** - Changes in existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Removed features
- **Fixed** - Bug fixes
- **Security** - Vulnerability fixes
