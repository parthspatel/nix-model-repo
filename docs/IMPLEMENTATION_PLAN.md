# Implementation Plan

## Overview

This document outlines the step-by-step implementation plan for the Nix Model Repo Plugin. We follow a bottom-up approach: define interfaces first, implement core utilities, then build higher-level abstractions.

---

## Phase 1: Project Scaffolding

### 1.1 Directory Structure

```
nix-huggingface/
├── flake.nix                 # Main entry point
├── flake.lock
├── lib/
│   ├── default.nix           # Library exports
│   ├── types.nix             # Type definitions & validation
│   ├── fetchModel.nix        # Core fetchModel function
│   ├── sources/
│   │   ├── default.nix       # Source adapter framework
│   │   ├── factories.nix     # Source factories (mkMlflow, etc.)
│   │   └── huggingface.nix   # HuggingFace adapter
│   ├── validation/
│   │   ├── default.nix       # Validation framework
│   │   ├── presets.nix       # Validation presets
│   │   └── validators.nix    # Built-in validators
│   └── integration.nix       # HF cache integration
├── fetchers/
│   ├── common.sh             # Shared shell utilities
│   └── huggingface.sh        # HuggingFace fetcher script
└── models/
    └── definitions.nix       # Model registry definitions
```

### 1.2 Implementation Order

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         IMPLEMENTATION ORDER                                 │
│                                                                              │
│  Layer 0: Scaffolding                                                        │
│  ─────────────────────                                                       │
│  flake.nix (skeleton) ─────────────────────────────────────────────────────▶│
│                                                                              │
│  Layer 1: Types & Interfaces                                                 │
│  ───────────────────────────                                                 │
│  lib/types.nix ────────────────────────────────────────────────────────────▶│
│                                                                              │
│  Layer 2: Shell Utilities                                                    │
│  ────────────────────────                                                    │
│  fetchers/common.sh ───────────────────────────────────────────────────────▶│
│                                                                              │
│  Layer 3: Source Adapters                                                    │
│  ────────────────────────                                                    │
│  lib/sources/default.nix ──┬── lib/sources/huggingface.nix                  │
│                            └── lib/sources/factories.nix ──────────────────▶│
│                                                                              │
│  Layer 4: Fetcher Scripts                                                    │
│  ────────────────────────                                                    │
│  fetchers/huggingface.sh ──────────────────────────────────────────────────▶│
│                                                                              │
│  Layer 5: Validation                                                         │
│  ───────────────────                                                         │
│  lib/validation/validators.nix ─┬── lib/validation/presets.nix              │
│                                 └── lib/validation/default.nix ────────────▶│
│                                                                              │
│  Layer 6: Integration                                                        │
│  ────────────────────                                                        │
│  lib/integration.nix ──────────────────────────────────────────────────────▶│
│                                                                              │
│  Layer 7: Core Function                                                      │
│  ──────────────────────                                                      │
│  lib/fetchModel.nix ───────────────────────────────────────────────────────▶│
│                                                                              │
│  Layer 8: Library Exports                                                    │
│  ────────────────────────                                                    │
│  lib/default.nix ──────────────────────────────────────────────────────────▶│
│                                                                              │
│  Layer 9: Flake Finalization                                                 │
│  ───────────────────────────                                                 │
│  flake.nix (complete) ─────────────────────────────────────────────────────▶│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 2: Interface Definitions

### 2.1 Source Adapter Interface

Every source adapter must implement this interface:

```nix
# Interface: SourceAdapter
{
  # Required: Build the FOD derivation for fetching
  # Returns: derivation (FOD with outputHash)
  mkFetchDerivation = {
    pkgs,           # nixpkgs
    name,           # derivation name
    hash,           # expected output hash (sha256)
    sourceConfig,   # source-specific configuration
    auth,           # authentication config
    network,        # network config (timeouts, proxy, etc.)
  }: derivation;

  # Required: Validate source configuration
  # Returns: { valid: bool, errors: [string] }
  validateConfig = sourceConfig: { valid, errors };

  # Required: List of impure env vars this source needs
  # Returns: [string]
  impureEnvVars = sourceConfig: [ "HF_TOKEN" ];

  # Required: List of build dependencies
  # Returns: [derivation]
  buildInputs = pkgs: [ pkgs.curl pkgs.jq ];

  # Optional: Extract metadata from source config
  # Returns: { org, model, revision, ... }
  extractMeta = sourceConfig: { ... };
}
```

### 2.2 Validator Interface

Every validator must implement this interface:

```nix
# Interface: Validator
{
  name = "validator-name";           # Unique identifier
  description = "What it checks";    # Human-readable description
  command = "shell script";          # Script with $src available
  onFailure = "abort";               # abort | warn | skip
  timeout = 300;                     # Timeout in seconds
}
```

### 2.3 FetchModel Config Interface

The main function accepts this configuration:

```nix
# Interface: FetchModelConfig
{
  # Required
  name = "model-name";               # Derivation name
  source = { ... };                  # Exactly one source type
  hash = "sha256-...";               # Expected output hash

  # Optional
  validation = { ... };              # Validation config
  integration = { ... };             # Integration config
  network = { ... };                 # Network config
  auth = { ... };                    # Auth config
  meta = { ... };                    # Nix meta attributes
}
```

---

## Phase 3: Implementation Details

### 3.1 lib/types.nix

Purpose: Define and validate configuration types.

```nix
# Exports:
{
  # Source type validators
  sourceTypes = { huggingface, mlflow, s3, git-lfs, git-xet, url, ollama };

  # Validate a source config, return { valid, errors, sourceType }
  validateSource = sourceConfig: { ... };

  # Validate full fetchModel config
  validateConfig = config: { ... };

  # Type coercion helpers
  normalizeHash = hash: "sha256-...";
}
```

### 3.2 lib/sources/default.nix

Purpose: Source adapter framework and dispatch.

```nix
# Exports:
{
  # Get adapter for a source type
  getAdapter = sourceType: adapter;

  # All available adapters
  adapters = { huggingface, mlflow, s3, ... };

  # Dispatch: given source config, return the right adapter
  dispatch = sourceConfig: adapter;
}
```

### 3.3 lib/sources/huggingface.nix

Purpose: HuggingFace-specific source adapter.

```nix
# Implements SourceAdapter interface
{
  mkFetchDerivation = { ... }: pkgs.stdenvNoCC.mkDerivation {
    # FOD settings
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = hash;

    # Builder
    builder = ./fetchers/huggingface.sh;

    # Environment
    REPO = sourceConfig.repo;
    REVISION = sourceConfig.revision or "main";
    # ...
  };

  validateConfig = sourceConfig: { ... };
  impureEnvVars = sourceConfig: [ "HF_TOKEN" ];
  buildInputs = pkgs: [ pkgs.curl pkgs.jq pkgs.cacert ];
  extractMeta = sourceConfig: { org, model, revision };
}
```

### 3.4 lib/validation/default.nix

Purpose: Validation framework.

```nix
# Exports:
{
  # Build validation derivation
  mkValidationDerivation = {
    name,
    src,              # FOD output
    validators,       # List of validators to run
    onFailure,        # Global failure handling
  }: derivation;

  # Merge validators from preset + custom
  mergeValidators = preset: custom: [ ... ];

  # Re-export presets and validators
  inherit presets validators;
}
```

### 3.5 lib/fetchModel.nix

Purpose: Core function that orchestrates everything.

```nix
# Main function
fetchModel = pkgs: config:
  let
    # 1. Validate config
    validated = types.validateConfig config;

    # 2. Get source adapter
    adapter = sources.dispatch config.source;

    # 3. Build FOD (Phase 1)
    rawModel = adapter.mkFetchDerivation {
      inherit pkgs;
      inherit (config) name hash;
      sourceConfig = config.source;
      auth = config.auth or {};
      network = config.network or {};
    };

    # 4. Build validation derivation (Phase 2)
    validatedModel = validation.mkValidationDerivation {
      inherit (config) name;
      src = rawModel;
      validators = validation.mergeValidators
        (config.validation or {})
        [];
      onFailure = config.validation.onFailure or "abort";
    };

    # 5. Add passthru and meta
  in validatedModel // {
    passthru = {
      raw = rawModel;
      meta = adapter.extractMeta config.source;
    };
    inherit (config) meta;
  };
```

### 3.6 fetchers/common.sh

Purpose: Shared shell utilities for all fetchers.

```bash
# Functions:
# - log_info, log_warn, log_error
# - download_with_progress
# - create_hf_blob
# - create_hf_snapshot
# - write_metadata
# - handle_http_error
# - retry_with_backoff
```

### 3.7 fetchers/huggingface.sh

Purpose: Download from HuggingFace Hub.

```bash
# Steps:
# 1. Resolve revision to commit SHA
# 2. Get file list from API
# 3. Filter files if patterns specified
# 4. Download each file
# 5. Create HF cache structure (blobs/, refs/, snapshots/)
# 6. Write metadata
```

---

## Phase 4: Testing Strategy

### 4.1 Unit Tests

```nix
# tests/unit/types.nix
# Test type validation functions

# tests/unit/sources.nix
# Test source adapter dispatch

# tests/unit/validation.nix
# Test validator merging
```

### 4.2 Integration Tests

```bash
# Test with a small public model
nix build .#models.x86_64-linux.test-model

# Verify HF cache structure
ls -la result/blobs/
ls -la result/snapshots/
```

### 4.3 End-to-End Test

```nix
# Fetch a real model and verify it works
{
  test-phi-2 = fetchModel pkgs {
    name = "phi-2-test";
    source.huggingface = {
      repo = "microsoft/phi-2";
      files = [ "config.json" ];  # Just config for fast test
    };
    hash = "sha256-...";  # Will get from prefetch
  };
}
```

---

## Phase 5: Implementation Checkpoints

### Checkpoint 1: Scaffolding Complete
- [ ] flake.nix skeleton builds
- [ ] Directory structure created
- [ ] lib/default.nix exports empty attrset

### Checkpoint 2: Types Working
- [ ] lib/types.nix validates source configs
- [ ] Error messages are helpful
- [ ] Hash normalization works

### Checkpoint 3: Source Adapter Working
- [ ] lib/sources/huggingface.nix creates FOD
- [ ] FOD builds with fake hash (gets real hash in error)
- [ ] Fetcher script downloads files

### Checkpoint 4: Validation Working
- [ ] Validation derivation runs validators
- [ ] Presets apply correctly
- [ ] onFailure handling works

### Checkpoint 5: Integration Working
- [ ] Full fetchModel pipeline works
- [ ] HF cache structure is correct
- [ ] passthru.raw accessible

### Checkpoint 6: Flake Complete
- [ ] lib.fetchModel works
- [ ] lib.sources factories work
- [ ] lib.validation presets work
- [ ] models.${system} exports work

---

## Detailed File Specifications

### File: flake.nix (Skeleton)

```nix
{
  description = "Nix Model Repo Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  in {
    lib = import ./lib { inherit (nixpkgs) lib; };

    # Per-system outputs
    packages = forAllSystems (system: {
      # Will add CLI tool here
    });
  };
}
```

### File: lib/default.nix

```nix
{ lib }:

let
  types = import ./types.nix { inherit lib; };
  sources = import ./sources { inherit lib; };
  validation = import ./validation { inherit lib; };
  integration = import ./integration.nix { inherit lib; };
in
{
  # Main API
  fetchModel = pkgs: import ./fetchModel.nix { inherit lib pkgs types sources validation integration; };

  # Source factories
  inherit (sources) factories;
  sources = sources.factories;

  # Validation
  validation = {
    inherit (validation) presets validators mkValidator;
  };

  # Integration
  inherit (integration) mkShellHook mkHfSymlinks;

  # Utilities
  inherit (types) validateConfig normalizeHash;
}
```

---

## Next: Begin Implementation

Starting with:
1. Create directory structure
2. Implement flake.nix skeleton
3. Implement lib/types.nix
4. Implement fetchers/common.sh
5. Implement lib/sources/huggingface.nix
6. Continue up the stack...
