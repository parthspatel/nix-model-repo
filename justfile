# nix-model-repo justfile
# Run `just` or `just help` to see available recipes

# Auto-detect system architecture
system := `nix eval --impure --raw --expr 'builtins.currentSystem'`

# Default recipe: show help
default:
    @just --list --unsorted

# ============================================================================
# Development Environment
# ============================================================================

# Enter the default development shell
dev:
    nix develop

# Enter the documentation dev shell
dev-docs:
    nix develop .#docs

# Enter the minimal CI dev shell
dev-ci:
    nix develop .#ci

# ============================================================================
# Testing
# ============================================================================

# Run all tests (unit + integration)
test:
    nix build .#checks.{{system}}.all-tests --print-build-logs

# Run unit tests only
test-unit:
    nix build .#checks.{{system}}.unit-tests --print-build-logs

# Run integration tests only
test-integration:
    nix build .#checks.{{system}}.integration-tests --print-build-logs

# Run all flake checks
check:
    nix flake check

# Run all flake checks for all systems
check-all:
    nix flake check --all-systems

# ============================================================================
# Code Quality
# ============================================================================

# Format all code (nix, shell, markdown)
fmt:
    nix fmt

# Check formatting without making changes
fmt-check:
    nix fmt -- --check .

# Run shellcheck on shell scripts
lint:
    shellcheck fetchers/*.sh scripts/*.sh

# Lint GitHub Actions workflows
lint-actions:
    actionlint

# Run all linters
lint-all: lint lint-actions

# ============================================================================
# Documentation
# ============================================================================

# Build documentation
docs:
    nix build .#docs --print-build-logs

# Serve docs with live reload (requires docs dev shell)
docs-serve:
    cd docs/sphinx && sphinx-autobuild . _build/html --port 8000 --open-browser

# Clean documentation build artifacts
docs-clean:
    rm -rf docs/sphinx/_build result

# ============================================================================
# Version Management
# ============================================================================

# Show current version
version:
    @cat VERSION

# Bump version (level: major, minor, patch)
version-bump level:
    ./scripts/bump-version.sh {{level}}

# ============================================================================
# Build & Evaluation
# ============================================================================

# Evaluate the flake (smoke test)
eval:
    nix flake show

# Evaluate and show model definitions as JSON
eval-models:
    nix eval .#modelDefs --json | jq

# Build a specific model (usage: just build-model bert-base)
build-model name:
    nix build .#models.{{system}}.{{name}} --print-build-logs

# ============================================================================
# Prefetch & Hashing
# ============================================================================

# Get hash for a HuggingFace model (usage: just prefetch google-bert/bert-base-uncased)
prefetch repo:
    nix-prefetch-url --unpack "https://huggingface.co/{{repo}}/resolve/main" 2>/dev/null || \
    echo "Note: For HuggingFace models, use: nix run nixpkgs#nix-prefetch -- fetchFromGitHub --owner huggingface --repo {{repo}}"

# Prefetch a git repository
prefetch-git url rev="HEAD":
    nix-prefetch-git {{url}} --rev {{rev}}

# ============================================================================
# Flake Management
# ============================================================================

# Update all flake inputs
update:
    nix flake update

# Update a specific flake input
update-input name:
    nix flake lock --update-input {{name}}

# ============================================================================
# Release
# ============================================================================

# Create a release (bumps version, commits, and tags)
release level:
    #!/usr/bin/env bash
    set -euo pipefail
    just version-bump {{level}}
    VERSION=$(cat VERSION)
    git add VERSION
    git commit -m "chore: bump version to ${VERSION}"
    git tag -a "v${VERSION}" -m "Release v${VERSION}"
    echo "Created release v${VERSION}"
    echo "Run 'git push && git push --tags' to publish"

# ============================================================================
# CI & Maintenance
# ============================================================================

# Run CI workflow locally with act
ci-local job="check":
    act -j {{job}}

# Run all CI checks locally (without act)
ci-check: fmt-check lint-all test check

# Run Nix garbage collection
gc:
    nix-collect-garbage

# Run aggressive Nix garbage collection (deletes old generations)
gc-aggressive:
    nix-collect-garbage -d

# Remove Nix build artifacts and result symlinks
clean:
    rm -rf result result-*
    find . -name 'result' -type l -delete

# Deep clean: clean + gc
clean-deep: clean gc

# ============================================================================
# Shell Script Validation
# ============================================================================

# Validate shell scripts thoroughly
shell-check:
    shellcheck -x -s bash fetchers/*.sh scripts/*.sh

# Format shell scripts
shell-fmt:
    shfmt -w -i 2 -ci fetchers/*.sh scripts/*.sh

# Check shell script formatting
shell-fmt-check:
    shfmt -d -i 2 -ci fetchers/*.sh scripts/*.sh

# ============================================================================
# Help & Info
# ============================================================================

# Show detailed help
help:
    @echo "nix-model-repo development commands"
    @echo ""
    @echo "Usage: just <recipe>"
    @echo ""
    @just --list --unsorted

# Show system information
info:
    @echo "System: {{system}}"
    @echo "Version: $(cat VERSION)"
    @echo "Nix version: $(nix --version)"
