# Nix Model Repo Plugin - Architecture Design

## Table of Contents

1. [Overview](#1-overview)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Directory Structure](#3-directory-structure)
4. [Core Components](#4-core-components)
5. [Data Flow](#5-data-flow)
6. [Nix Library Interface](#6-nix-library-interface)
7. [Fetcher Implementation](#7-fetcher-implementation)
8. [Validation Framework](#8-validation-framework)
9. [HuggingFace Cache Integration](#9-huggingface-cache-integration)
10. [NixOS Module](#10-nixos-module)
11. [Home Manager Module](#11-home-manager-module)
12. [CLI Tool](#12-cli-tool)
13. [Error Handling](#13-error-handling)
14. [Configuration Schema](#14-configuration-schema)
15. [Validation Presets & Patterns](#15-validation-presets--patterns)
16. [Source Reuse Patterns](#16-source-reuse-patterns)
17. [Flake Structure & Exports](#17-flake-structure--exports)

---

## 1. Overview

### 1.1 Design Principles

1. **FOD-First**: All network operations happen in Fixed Output Derivations
2. **Two-Phase Architecture**: Fetch (FOD) → Validate (regular derivation)
3. **Composability**: Works with flakes, NixOS modules, Home Manager, dev shells
4. **Minimal Dependencies**: Shell-based fetcher using standard Unix tools
5. **Explicit Over Magic**: Clear configuration, predictable behavior

### 1.2 Key Decisions (from Gaps Analysis)

| Decision               | Choice                    | Rationale                        |
| ---------------------- | ------------------------- | -------------------------------- |
| Fetcher implementation | Shell script (v1)         | Simple, portable, no build step  |
| File discovery         | API + explicit fallback   | Good UX with override capability |
| Hash granularity       | Single output hash        | Standard FOD pattern             |
| Version stability      | Commit SHA + content hash | Human-readable + reproducible    |
| Model registry         | Curated + community       | Quality + scalability            |

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER INTERFACE                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   flake.nix │  │ NixOS Module│  │ Home Manager│  │ CLI: nix-model-repo   │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
└─────────┼────────────────┼────────────────┼────────────────────┼────────────┘
          │                │                │                    │
          ▼                ▼                ▼                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              NIX LIBRARY                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  lib.fetchModel { source, hash, validation, integration, ... }      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│         ┌──────────────────────────┼──────────────────────────┐             │
│         ▼                          ▼                          ▼             │
│  ┌─────────────┐           ┌─────────────┐           ┌─────────────┐        │
│  │  Source     │           │  Validation │           │ Integration │        │
│  │  Adapters   │           │  Framework  │           │  Layer      │        │
│  └─────────────┘           └─────────────┘           └─────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
          │                          │                          │
          ▼                          ▼                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DERIVATIONS                                     │
│                                                                              │
│  ┌─────────────────────────┐    ┌─────────────────────────┐                 │
│  │   PHASE 1: FOD FETCH    │───▶│  PHASE 2: VALIDATION   │                 │
│  │   (network access)      │    │  (no network)          │                 │
│  │   Output: raw model     │    │  Output: validated     │                 │
│  └─────────────────────────┘    └─────────────────────────┘                 │
│                                              │                               │
│                                              ▼                               │
│                               ┌─────────────────────────┐                   │
│                               │  PHASE 3: INTEGRATION   │                   │
│                               │  (HF cache, symlinks)   │                   │
│                               └─────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              NIX STORE                                       │
│  /nix/store/<hash>-model-name-raw      (Phase 1 output)                     │
│  /nix/store/<hash>-model-name          (Phase 2 output, user-facing)        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Directory Structure

```
nix-huggingface/
├── flake.nix                    # Main flake entry point
├── flake.lock
├── default.nix                  # Legacy Nix support (imports flake)
│
├── lib/                         # Nix library functions
│   ├── default.nix              # Main lib export
│   ├── fetchModel.nix           # Core fetchModel function
│   ├── sources/                 # Source-specific adapters
│   │   ├── huggingface.nix
│   │   ├── mlflow.nix
│   │   ├── git-lfs.nix
│   │   ├── git-xet.nix
│   │   ├── s3.nix
│   │   ├── http.nix
│   │   └── ollama.nix
│   ├── validation.nix           # Validation framework
│   ├── integration.nix          # HF cache, wrappers
│   ├── utils.nix                # Helper functions
│   └── types.nix                # Type definitions & validation
│
├── fetchers/                    # Shell scripts for FOD phase
│   ├── common.sh                # Shared utilities
│   ├── huggingface.sh           # HuggingFace fetcher
│   ├── git-lfs.sh               # Git LFS fetcher
│   ├── git-xet.sh               # Git-Xet fetcher
│   ├── s3.sh                    # S3 fetcher
│   ├── http.sh                  # Generic HTTP fetcher
│   └── ollama.sh                # Ollama fetcher
│
├── validators/                  # Validation scripts
│   ├── modelscan.sh             # modelscan wrapper
│   ├── pickle-scan.py           # Pickle vulnerability scanner
│   └── custom-template.sh       # Template for custom validators
│
├── modules/                     # NixOS/Home Manager modules
│   ├── nixos.nix                # NixOS module
│   └── home-manager.nix         # Home Manager module
│
├── models/                      # Pre-defined model registry
│   ├── default.nix              # Registry entry point
│   ├── huggingface/             # HuggingFace models by org
│   │   ├── meta-llama.nix
│   │   ├── mistralai.nix
│   │   ├── microsoft.nix
│   │   └── ...
│   └── ollama/                  # Ollama models
│       └── default.nix
│
├── cli/                         # CLI tool source
│   └── nix-model-repo.sh          # Main CLI script
│
├── tests/                       # Test suite
│   ├── unit/                    # Pure Nix function tests
│   ├── integration/             # Mock server tests
│   └── e2e/                     # Real model tests
│
└── docs/                        # Documentation
    ├── FUNCTIONAL_REQUIREMENTS.md
    ├── ARCHITECTURE.md          # This file
    └── USAGE.md                 # User guide
```

---

## 4. Core Components

### 4.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              lib/fetchModel.nix                              │
│                                                                              │
│  Inputs:                          Outputs:                                   │
│  - source (huggingface, s3, ...)  - derivation (validated model)            │
│  - hash (sha256)                  - passthru.raw (FOD output)               │
│  - validation (hooks, scanners)   - passthru.meta (model metadata)          │
│  - integration (hf cache, env)                                              │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                         DISPATCH BY SOURCE                            │   │
│  │                                                                       │   │
│  │   source.huggingface → lib/sources/huggingface.nix                   │   │
│  │   source.s3          → lib/sources/s3.nix                            │   │
│  │   source.git-lfs     → lib/sources/git-lfs.nix                       │   │
│  │   source.git-xet     → lib/sources/git-xet.nix                       │   │
│  │   source.url         → lib/sources/http.nix                          │   │
│  │   source.ollama      → lib/sources/ollama.nix                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      SOURCE ADAPTER OUTPUT                            │   │
│  │                                                                       │   │
│  │   {                                                                   │   │
│  │     fetcher = ./fetchers/huggingface.sh;                             │   │
│  │     fetcherArgs = { repo, revision, files, ... };                    │   │
│  │     dependencies = [ curl jq cacert ];                               │   │
│  │     impureEnvVars = [ "HF_TOKEN" ];                                  │   │
│  │   }                                                                   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      BUILD PHASE 1: FOD                               │   │
│  │                                                                       │   │
│  │   pkgs.stdenvNoCC.mkDerivation {                                     │   │
│  │     name = "${name}-raw";                                            │   │
│  │     outputHash = hash;                                               │   │
│  │     outputHashAlgo = "sha256";                                       │   │
│  │     outputHashMode = "recursive";                                    │   │
│  │     builder = fetcher;                                               │   │
│  │     ...                                                              │   │
│  │   }                                                                   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      BUILD PHASE 2: VALIDATION                        │   │
│  │                                                                       │   │
│  │   pkgs.stdenvNoCC.mkDerivation {                                     │   │
│  │     name = name;                                                     │   │
│  │     src = phase1;                                                    │   │
│  │     buildPhase = validation.script;                                  │   │
│  │     ...                                                              │   │
│  │   }                                                                   │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Component Responsibilities

| Component             | Responsibility                                                |
| --------------------- | ------------------------------------------------------------- |
| `lib/fetchModel.nix`  | Main entry point, config validation, derivation orchestration |
| `lib/sources/*.nix`   | Source-specific URL building, auth handling, file discovery   |
| `lib/validation.nix`  | Validator execution, failure handling, result aggregation     |
| `lib/integration.nix` | HF cache structure, symlinks, environment variables           |
| `fetchers/*.sh`       | Actual download logic, progress reporting, error handling     |
| `validators/*.sh`     | Security scanning, model verification                         |
| `modules/*.nix`       | NixOS/Home Manager integration, system-wide config            |

---

## 5. Data Flow

### 5.1 Fetch Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FETCH FLOW                                      │
│                                                                              │
│  User calls:                                                                 │
│  fetchModel {                                                                │
│    source.huggingface.repo = "meta-llama/Llama-2-7b-hf";                    │
│    hash = "sha256-abc123...";                                               │
│  }                                                                           │
│                                                                              │
│  Step 1: Config Validation                                                   │
│  ────────────────────────────                                                │
│  lib/types.nix validates:                                                    │
│  - source has exactly one type defined                                       │
│  - hash is valid SHA256 format                                              │
│  - required fields present                                                   │
│           │                                                                  │
│           ▼                                                                  │
│  Step 2: Source Adapter                                                      │
│  ──────────────────────                                                      │
│  lib/sources/huggingface.nix:                                               │
│  - Builds file list URL: https://huggingface.co/api/models/.../tree/main    │
│  - Constructs download URLs for each file                                    │
│  - Returns: { fetcher, fetcherArgs, deps, impureEnvVars }                   │
│           │                                                                  │
│           ▼                                                                  │
│  Step 3: FOD Derivation (Phase 1)                                           │
│  ────────────────────────────────                                            │
│  mkDerivation {                                                              │
│    outputHash = "sha256-abc123...";                                         │
│    builder = fetchers/huggingface.sh;                                       │
│    # Runs with network access                                                │
│  }                                                                           │
│           │                                                                  │
│           ▼                                                                  │
│  Step 4: Fetcher Execution                                                   │
│  ─────────────────────────                                                   │
│  fetchers/huggingface.sh:                                                   │
│  - Reads HF_TOKEN from environment                                          │
│  - Downloads each file with curl                                            │
│  - Creates HuggingFace cache structure (blobs/, refs/, snapshots/)          │
│  - Writes metadata to .nix-model-repo-meta.json                               │
│           │                                                                  │
│           ▼                                                                  │
│  Step 5: Hash Verification                                                   │
│  ─────────────────────────                                                   │
│  Nix automatically verifies outputHash matches                               │
│  - Match: derivation succeeds, stored at /nix/store/<hash>-model-raw        │
│  - Mismatch: derivation fails with hash error                               │
│           │                                                                  │
│           ▼                                                                  │
│  Step 6: Validation Derivation (Phase 2)                                    │
│  ───────────────────────────────────────                                     │
│  mkDerivation {                                                              │
│    src = phase1Output;                                                       │
│    # Runs validators, no network access                                      │
│  }                                                                           │
│           │                                                                  │
│           ▼                                                                  │
│  Step 7: Output                                                              │
│  ─────────────                                                               │
│  /nix/store/<hash>-llama-2-7b-hf/                                           │
│  ├── blobs/                                                                  │
│  ├── refs/                                                                   │
│  ├── snapshots/                                                              │
│  └── .nix-model-repo-meta.json                                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Authentication Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AUTHENTICATION FLOW                                 │
│                                                                              │
│  Priority order for credential resolution:                                   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  1. Explicit tokenFile in config                                    │    │
│  │     auth.tokenFile = "/run/secrets/hf-token"                       │    │
│  │     → Read file contents at build time                              │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                          │ not set                                           │
│                          ▼                                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  2. Environment variable                                            │    │
│  │     HF_TOKEN, AWS_ACCESS_KEY_ID, XET_TOKEN, etc.                   │    │
│  │     → Passed via impureEnvVars                                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                          │ not set                                           │
│                          ▼                                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  3. Standard credential files                                       │    │
│  │     ~/.cache/huggingface/token                                     │    │
│  │     ~/.aws/credentials                                              │    │
│  │     ~/.xet/credentials                                              │    │
│  │     → Fetcher script reads if accessible                            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                          │ not set                                           │
│                          ▼                                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  4. Anonymous access                                                │    │
│  │     → Works for public models only                                  │    │
│  │     → Fails with helpful error for gated models                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Nix Library Interface

### 6.1 Main Entry Point: `lib.fetchModel`

```nix
# lib/fetchModel.nix
{ lib, pkgs, ... }:

{
  # Main function to fetch and validate a model
  fetchModel = {
    # Required
    name,           # string: Derivation name (e.g., "llama-2-7b")
    source,         # attrset: One of the source types (see below)
    hash,           # string: SHA256 hash of output (e.g., "sha256-abc...")

    # Optional: Validation
    validation ? {
      enable = true;
      validators = [];  # Additional validators beyond defaults
      skipDefaults = false;  # Skip built-in security scans
      onFailure = "abort";  # abort | warn | skip
    },

    # Optional: Integration
    integration ? {
      huggingface = {
        enable = true;  # Create HF-compatible structure
        org = null;     # Override org name (default: from repo)
        model = null;   # Override model name (default: from repo)
      };
      environment = {};  # Extra env vars to set
    },

    # Optional: Network
    network ? {
      timeout.connect = 30;
      timeout.read = 300;
      retry.maxAttempts = 3;
      proxy = null;
    },

    # Optional: Authentication
    auth ? {
      tokenEnvVar = null;  # e.g., "HF_TOKEN"
      tokenFile = null;    # e.g., "/run/secrets/hf-token"
    },

    # Optional: Failure handling
    onFailure ? {
      action = "clean";  # clean | persist | retry
      notify = null;     # Script to run on failure
    },

    # Optional: Metadata
    meta ? {},  # Standard Nix meta attributes
  }:

  # Returns: derivation with validated model
  # passthru: { raw, meta, source }
  ...
}
```

### 6.2 Source Type Definitions

```nix
# lib/types.nix

sourceTypes = {
  # HuggingFace Hub
  huggingface = {
    repo = lib.mkOption {
      type = types.str;
      example = "meta-llama/Llama-2-7b-hf";
      description = "HuggingFace repository in org/model format";
    };
    revision = lib.mkOption {
      type = types.str;
      default = "main";
      description = "Branch, tag, or commit SHA";
    };
    files = lib.mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = "Glob patterns for files to download (null = all)";
    };
  };

  # Git LFS
  git-lfs = {
    url = types.str;         # Git repository URL
    rev = types.str;         # Commit SHA
    lfsFiles = types.listOf types.str;  # Patterns for LFS files
  };

  # Git-Xet
  git-xet = {
    url = types.str;         # Git repository URL
    rev = types.str;         # Commit SHA
    files = types.nullOr (types.listOf types.str);
    xet = {
      endpoint = types.str;  # Xet storage endpoint
    };
  };

  # S3
  s3 = {
    bucket = types.str;
    prefix = types.str;
    region = types.str;
    files = types.nullOr (types.listOf types.str);
  };

  # Direct HTTP URLs
  url = {
    urls = types.listOf (types.submodule {
      url = types.str;
      sha256 = types.str;
      filename = types.nullOr types.str;
    });
  };

  # Ollama
  ollama = {
    model = types.str;  # e.g., "llama2:7b"
  };

  # MLFlow
  mlflow = {
    trackingUri = types.str;
    modelName = types.str;
    modelVersion = types.nullOr types.str;
    modelStage = types.nullOr types.str;
  };
};
```

### 6.3 Library Exports

```nix
# lib/default.nix
{ lib, pkgs, ... }:

let
  fetchModel = import ./fetchModel.nix { inherit lib pkgs; };
  sources = import ./sources { inherit lib pkgs; };
  validation = import ./validation.nix { inherit lib pkgs; };
  integration = import ./integration.nix { inherit lib pkgs; };
  utils = import ./utils.nix { inherit lib; };
  types = import ./types.nix { inherit lib; };
in
{
  # Main API
  inherit fetchModel;

  # Source-specific fetchers (advanced use)
  fetchFromHuggingFace = sources.huggingface.fetch;
  fetchFromS3 = sources.s3.fetch;
  fetchFromGitLfs = sources.gitLfs.fetch;
  fetchFromGitXet = sources.gitXet.fetch;
  fetchFromUrl = sources.http.fetch;
  fetchFromOllama = sources.ollama.fetch;
  fetchFromMlflow = sources.mlflow.fetch;

  # Utilities
  prefetchModel = utils.prefetch;  # Get hash for a model
  mkHfCachePath = utils.mkHfCachePath;  # Generate HF cache path
  parseModelSpec = utils.parseModelSpec;  # Parse "hf:org/model@rev"

  # Validation helpers
  mkValidator = validation.mkValidator;
  validators = validation.builtinValidators;

  # Integration helpers
  mkHfSymlinks = integration.mkHfSymlinks;
  mkModelWrapper = integration.mkModelWrapper;

  # Type checking
  inherit types;
}
```

---

## 7. Fetcher Implementation

### 7.1 Common Utilities

```bash
# fetchers/common.sh - Shared utilities for all fetchers

set -euo pipefail

# Logging
log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# Progress bar for downloads
download_with_progress() {
    local url="$1"
    local output="$2"
    local token="${3:-}"

    local curl_opts=(
        --fail
        --location
        --retry 3
        --retry-delay 2
        --connect-timeout "${CONNECT_TIMEOUT:-30}"
        --max-time "${MAX_TIME:-0}"
        --progress-bar
        --output "$output"
    )

    if [[ -n "$token" ]]; then
        curl_opts+=(--header "Authorization: Bearer $token")
    fi

    if [[ -n "${BANDWIDTH_LIMIT:-}" ]]; then
        curl_opts+=(--limit-rate "$BANDWIDTH_LIMIT")
    fi

    curl "${curl_opts[@]}" "$url"
}

# Create HuggingFace-compatible blob storage
create_hf_blob() {
    local file="$1"
    local blobs_dir="$2"

    local sha256
    sha256=$(sha256sum "$file" | cut -d' ' -f1)

    mv "$file" "$blobs_dir/$sha256"
    echo "$sha256"
}

# Create snapshot symlinks pointing to blobs
create_hf_snapshot() {
    local blobs_dir="$1"
    local snapshots_dir="$2"
    local commit_sha="$3"
    local filename="$4"
    local blob_hash="$5"

    local snapshot_dir="$snapshots_dir/$commit_sha"
    mkdir -p "$snapshot_dir"

    # Create relative symlink: snapshots/<sha>/file → ../../blobs/<hash>
    ln -s "../../blobs/$blob_hash" "$snapshot_dir/$filename"
}

# Write model metadata
write_metadata() {
    local output="$1"
    local source="$2"
    local fetched_at="$3"

    cat > "$output/.nix-model-repo-meta.json" << EOF
{
  "source": "$source",
  "fetchedAt": "$fetched_at",
  "nixAiModelVersion": "1.0.0"
}
EOF
}
```

### 7.2 HuggingFace Fetcher

```bash
#!/usr/bin/env bash
# fetchers/huggingface.sh - HuggingFace Hub fetcher

source @common@

# Required environment variables (set by Nix derivation)
: "${REPO:?REPO is required}"        # e.g., "meta-llama/Llama-2-7b-hf"
: "${REVISION:?REVISION is required}" # e.g., "main" or commit SHA
: "${out:?out is required}"          # Nix output path

# Optional
FILES="${FILES:-}"           # Space-separated file patterns
HF_TOKEN="${HF_TOKEN:-}"     # Auth token

# Constants
HF_API="https://huggingface.co/api"
HF_BASE="https://huggingface.co"

log_info "Fetching HuggingFace model: $REPO @ $REVISION"

# Step 1: Resolve revision to commit SHA
resolve_revision() {
    local api_url="$HF_API/models/$REPO/revision/$REVISION"
    local headers=()

    if [[ -n "$HF_TOKEN" ]]; then
        headers+=(--header "Authorization: Bearer $HF_TOKEN")
    fi

    local response
    response=$(curl --silent --fail "${headers[@]}" "$api_url") || {
        log_error "Failed to resolve revision: $REVISION"
        log_error "If this is a gated model, ensure HF_TOKEN is set"
        exit 1
    }

    echo "$response" | jq -r '.sha'
}

# Step 2: Get file list
get_file_list() {
    local commit_sha="$1"
    local api_url="$HF_API/models/$REPO/tree/$commit_sha"
    local headers=()

    if [[ -n "$HF_TOKEN" ]]; then
        headers+=(--header "Authorization: Bearer $HF_TOKEN")
    fi

    local response
    response=$(curl --silent --fail "${headers[@]}" "$api_url") || {
        log_error "Failed to get file list"
        exit 1
    }

    # Filter files if patterns specified
    if [[ -n "$FILES" ]]; then
        # Apply glob patterns (simplified - real impl would be more robust)
        echo "$response" | jq -r '.[].path' | while read -r file; do
            for pattern in $FILES; do
                # shellcheck disable=SC2053
                if [[ "$file" == $pattern ]]; then
                    echo "$file"
                    break
                fi
            done
        done
    else
        echo "$response" | jq -r '.[].path'
    fi
}

# Step 3: Download files
download_files() {
    local commit_sha="$1"
    local files="$2"
    local temp_dir="$3"

    local blobs_dir="$temp_dir/blobs"
    local snapshots_dir="$temp_dir/snapshots"
    local refs_dir="$temp_dir/refs"

    mkdir -p "$blobs_dir" "$snapshots_dir/$commit_sha" "$refs_dir"

    # Write refs/main (or the revision name)
    echo "$commit_sha" > "$refs_dir/main"

    echo "$files" | while read -r file; do
        [[ -z "$file" ]] && continue

        log_info "Downloading: $file"
        local url="$HF_BASE/$REPO/resolve/$commit_sha/$file"
        local temp_file="$temp_dir/download_temp"

        download_with_progress "$url" "$temp_file" "$HF_TOKEN"

        # Create blob and symlink
        local blob_hash
        blob_hash=$(create_hf_blob "$temp_file" "$blobs_dir")
        create_hf_snapshot "$blobs_dir" "$snapshots_dir" "$commit_sha" "$file" "$blob_hash"

        log_info "Downloaded: $file → blobs/$blob_hash"
    done
}

# Main execution
main() {
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    # Resolve revision to commit
    log_info "Resolving revision: $REVISION"
    local commit_sha
    commit_sha=$(resolve_revision)
    log_info "Resolved to commit: $commit_sha"

    # Get file list
    log_info "Getting file list..."
    local files
    files=$(get_file_list "$commit_sha")

    # Download all files
    download_files "$commit_sha" "$files" "$temp_dir"

    # Write metadata
    write_metadata "$temp_dir" "huggingface:$REPO@$commit_sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Move to output
    mkdir -p "$out"
    cp -r "$temp_dir"/* "$out"/

    log_info "Successfully fetched model to: $out"
}

main "$@"
```

### 7.3 Fetcher Derivation Template

```nix
# lib/sources/huggingface.nix
{ lib, pkgs, ... }:

{
  fetch = { repo, revision ? "main", files ? null, auth ? {}, network ? {}, ... }:

  let
    fetcher = pkgs.substituteAll {
      src = ../../fetchers/huggingface.sh;
      common = ../../fetchers/common.sh;
      isExecutable = true;
    };

    # Files as space-separated string for shell
    filesArg = if files == null then "" else lib.concatStringsSep " " files;

  in pkgs.stdenvNoCC.mkDerivation {
    name = "${lib.replaceStrings ["/"] ["-"] repo}-raw";

    # FOD settings
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    # outputHash set by caller

    nativeBuildInputs = [ pkgs.curl pkgs.jq pkgs.cacert ];

    # Impure env vars for auth
    impureEnvVars = lib.optionals (auth.tokenEnvVar != null) [
      auth.tokenEnvVar
    ] ++ [ "HF_TOKEN" ];  # Always allow HF_TOKEN

    # Fetcher environment
    REPO = repo;
    REVISION = revision;
    FILES = filesArg;

    # Network settings
    CONNECT_TIMEOUT = toString (network.timeout.connect or 30);
    MAX_TIME = toString (network.timeout.read or 0);
    BANDWIDTH_LIMIT = network.bandwidth.limit or "";

    builder = fetcher;
  };
}
```

---

## 8. Validation Framework

### 8.1 Validation Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         VALIDATION DERIVATION                                │
│                                                                              │
│  Input: FOD output (/nix/store/<hash>-model-raw)                            │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        VALIDATOR CHAIN                                 │  │
│  │                                                                        │  │
│  │   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                 │  │
│  │   │ modelscan   │ → │ pickle-scan │ → │   custom    │ → ...          │  │
│  │   │ (default)   │   │ (default)   │   │ validators  │                 │  │
│  │   └─────────────┘   └─────────────┘   └─────────────┘                 │  │
│  │                                                                        │  │
│  │   Each validator:                                                      │  │
│  │   - Receives: $src (model path), $out (output path)                   │  │
│  │   - Returns: exit code 0 (pass) or non-zero (fail)                    │  │
│  │   - Stdout/stderr: logged for debugging                               │  │
│  │                                                                        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        FAILURE HANDLING                                │  │
│  │                                                                        │  │
│  │   onFailure = "abort"  → Derivation fails, no output                  │  │
│  │   onFailure = "warn"   → Log warning, continue                        │  │
│  │   onFailure = "skip"   → Silently continue                            │  │
│  │                                                                        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        OUTPUT GENERATION                               │  │
│  │                                                                        │  │
│  │   - Copy validated model to $out                                       │  │
│  │   - Update metadata with validation results                           │  │
│  │   - Create any integration structures (HF cache format)               │  │
│  │                                                                        │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  Output: /nix/store/<hash>-model-name (validated, ready to use)             │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Validation Implementation

```nix
# lib/validation.nix
{ lib, pkgs, ... }:

rec {
  # Built-in validators
  builtinValidators = {
    modelscan = mkValidator {
      name = "modelscan";
      description = "Scan for malicious serialized objects";
      command = ''
        ${pkgs.python3Packages.modelscan}/bin/modelscan --path "$src"
      '';
      # Fail if modelscan finds issues
      onFailure = "abort";
    };

    pickleScan = mkValidator {
      name = "pickle-scan";
      description = "Scan for dangerous pickle operations";
      command = ''
        ${pkgs.python3}/bin/python ${../validators/pickle-scan.py} "$src"
      '';
      onFailure = "abort";
    };

    checkRequiredFiles = { requiredFiles }: mkValidator {
      name = "check-required-files";
      description = "Verify required files are present";
      command = ''
        ${lib.concatMapStringsSep "\n" (f: ''
          if [[ ! -f "$src/${f}" ]]; then
            echo "ERROR: Required file missing: ${f}" >&2
            exit 1
          fi
        '') requiredFiles}
      '';
      onFailure = "abort";
    };
  };

  # Create a validator specification
  mkValidator = {
    name,
    command,
    description ? "",
    onFailure ? "abort",  # abort | warn | skip
    timeout ? 300,
  }: {
    inherit name command description onFailure timeout;
  };

  # Build validation derivation
  mkValidationDerivation = {
    name,
    src,  # The FOD output
    validators ? [],
    skipDefaults ? false,
    integration ? {},
  }:
  let
    # Combine default and custom validators
    allValidators = (if skipDefaults then [] else [
      builtinValidators.modelscan
      builtinValidators.pickleScan
    ]) ++ validators;

    # Generate validation script
    validationScript = ''
      set -euo pipefail

      echo "Running ${toString (length allValidators)} validators..."

      ${lib.concatMapStringsSep "\n\n" (v: ''
        echo "=== Validator: ${v.name} ==="
        echo "${v.description}"

        set +e
        timeout ${toString v.timeout} bash -c ${lib.escapeShellArg v.command}
        exit_code=$?
        set -e

        if [[ $exit_code -ne 0 ]]; then
          echo "Validator ${v.name} failed with exit code $exit_code"
          ${if v.onFailure == "abort" then ''
            exit 1
          '' else if v.onFailure == "warn" then ''
            echo "WARNING: Continuing despite validation failure"
          '' else ''
            # skip - do nothing
            true
          ''}
        fi
      '') allValidators}

      echo "All validators passed!"
    '';

  in pkgs.stdenvNoCC.mkDerivation {
    inherit name;
    inherit src;

    buildPhase = ''
      runHook preBuild

      ${validationScript}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Copy validated model to output
      mkdir -p $out
      cp -r $src/* $out/

      # Update metadata with validation info
      ${pkgs.jq}/bin/jq '. + {
        "validation": {
          "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
          "validators": ${builtins.toJSON (map (v: v.name) allValidators)},
          "passed": true
        }
      }' $src/.nix-model-repo-meta.json > $out/.nix-model-repo-meta.json

      runHook postInstall
    '';
  };
}
```

---

## 9. HuggingFace Cache Integration

### 9.1 Cache Structure Builder

```nix
# lib/integration.nix
{ lib, pkgs, ... }:

{
  # Create HF-compatible cache structure in output
  mkHfStructure = {
    src,       # Source model files
    org,       # Organization name (e.g., "meta-llama")
    model,     # Model name (e.g., "Llama-2-7b-hf")
    revision,  # Commit SHA
  }:
  ''
    # The src already has HF structure from the fetcher
    # Just verify it's correct

    if [[ ! -d "$src/blobs" ]]; then
      echo "ERROR: Missing blobs directory" >&2
      exit 1
    fi

    if [[ ! -d "$src/snapshots" ]]; then
      echo "ERROR: Missing snapshots directory" >&2
      exit 1
    fi

    # Ensure refs/main exists
    if [[ ! -f "$src/refs/main" ]]; then
      mkdir -p "$out/refs"
      echo "${revision}" > "$out/refs/main"
    fi
  '';

  # Create symlinks in HF cache directory
  mkHfSymlinks = {
    modelPath,  # Path to model in Nix store
    org,
    model,
    cacheDir ? null,  # Override HF_HOME
  }:
  let
    hfDir = if cacheDir != null then cacheDir else "$HOME/.cache/huggingface/hub";
    linkName = "models--${org}--${model}";
  in pkgs.writeShellScript "setup-hf-symlinks" ''
    set -euo pipefail

    cache_dir="${hfDir}"
    mkdir -p "$cache_dir"

    link_path="$cache_dir/${linkName}"

    # Remove existing symlink if present
    if [[ -L "$link_path" ]]; then
      rm "$link_path"
    elif [[ -e "$link_path" ]]; then
      echo "WARNING: $link_path exists and is not a symlink, skipping"
      exit 0
    fi

    # Create symlink
    ln -s "${modelPath}" "$link_path"
    echo "Created symlink: $link_path → ${modelPath}"
  '';

  # Shell hook for dev shells
  mkShellHook = {
    models,  # List of { path, org, model }
  }:
  lib.concatMapStringsSep "\n" (m: ''
    # Setup HuggingFace cache for ${m.org}/${m.model}
    ${mkHfSymlinks {
      modelPath = m.path;
      inherit (m) org model;
    }}
  '') models;

  # Wrapper that sets environment variables
  mkModelWrapper = {
    program,
    models,  # List of { path, name, envVar }
  }:
  pkgs.writeShellScriptBin (baseNameOf program) ''
    ${lib.concatMapStringsSep "\n" (m: ''
      export ${m.envVar}="${m.path}"
    '') models}

    exec ${program} "$@"
  '';
}
```

### 9.2 Activation Script for Dev Shells

```nix
# Example: devShell with HuggingFace integration
{
  devShells.default = pkgs.mkShell {
    packages = [
      (nix-model-repo.lib.fetchModel {
        name = "llama-2-7b";
        source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
        hash = "sha256-...";
      })
    ];

    shellHook = ''
      # Automatically setup HuggingFace cache symlinks
      ${nix-model-repo.lib.mkShellHook {
        models = [{
          path = llama-model;
          org = "meta-llama";
          model = "Llama-2-7b-hf";
        }];
      }}

      # Also set environment for offline use
      export HF_HUB_OFFLINE=1
      export TRANSFORMERS_OFFLINE=1

      echo "Models ready:"
      echo "  - meta-llama/Llama-2-7b-hf"
    '';
  };
}
```

---

## 10. NixOS Module

```nix
# modules/nixos.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.model-repo;
  modelType = types.submodule {
    options = {
      source = mkOption {
        type = types.attrsOf types.anything;
        description = "Model source configuration";
      };
      hash = mkOption {
        type = types.str;
        description = "SHA256 hash of the model";
      };
      validation = mkOption {
        type = types.attrsOf types.anything;
        default = {};
        description = "Validation configuration";
      };
    };
  };
in {
  options.services.model-repo = {
    enable = mkEnableOption "AI model management";

    models = mkOption {
      type = types.attrsOf modelType;
      default = {};
      description = "Models to make available system-wide";
      example = literalExpression ''
        {
          llama-2-7b = {
            source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
            hash = "sha256-...";
          };
        }
      '';
    };

    cacheDir = mkOption {
      type = types.path;
      default = "/var/cache/model-repo";
      description = "Directory for model cache and HuggingFace symlinks";
    };

    allowedUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users allowed to access models";
    };

    huggingfaceIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Create HuggingFace-compatible cache structure";
    };
  };

  config = mkIf cfg.enable {
    # Build all models
    system.extraDependencies = mapAttrsToList (name: modelCfg:
      nix-model-repo.lib.fetchModel ({
        inherit name;
        inherit (modelCfg) source hash;
      } // modelCfg.validation)
    ) cfg.models;

    # Create cache directory
    systemd.tmpfiles.rules = [
      "d ${cfg.cacheDir} 0755 root root -"
      "d ${cfg.cacheDir}/huggingface 0755 root root -"
    ];

    # Create symlinks on activation
    system.activationScripts.model-repo = stringAfter [ "users" "groups" ] ''
      echo "Setting up AI model symlinks..."
      ${concatMapStringsSep "\n" (name: let
        model = cfg.models.${name};
        modelDrv = nix-model-repo.lib.fetchModel {
          inherit name;
          inherit (model) source hash;
        };
        # Extract org/model from source
        org = head (splitString "/" model.source.huggingface.repo);
        modelName = last (splitString "/" model.source.huggingface.repo);
      in ''
        ln -sfn ${modelDrv} ${cfg.cacheDir}/huggingface/models--${org}--${modelName}
      '') (attrNames cfg.models)}
    '';

    # Environment for accessing models
    environment.variables = {
      HF_HOME = "${cfg.cacheDir}/huggingface";
    };
  };
}
```

---

## 11. Home Manager Module

```nix
# modules/home-manager.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.model-repo;
in {
  options.programs.model-repo = {
    enable = mkEnableOption "AI model management for user";

    models = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          source = mkOption { type = types.attrsOf types.anything; };
          hash = mkOption { type = types.str; };
        };
      });
      default = {};
    };

    huggingfaceIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Create symlinks in ~/.cache/huggingface/hub";
    };

    offlineMode = mkOption {
      type = types.bool;
      default = true;
      description = "Set environment variables for offline HuggingFace usage";
    };
  };

  config = mkIf cfg.enable {
    # Build models and add to user packages (for GC root)
    home.packages = mapAttrsToList (name: modelCfg:
      nix-model-repo.lib.fetchModel {
        inherit name;
        inherit (modelCfg) source hash;
      }
    ) cfg.models;

    # Create symlinks
    home.activation.model-repo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      echo "Setting up AI model symlinks..."
      mkdir -p ~/.cache/huggingface/hub

      ${concatMapStringsSep "\n" (name: let
        model = cfg.models.${name};
        modelDrv = nix-model-repo.lib.fetchModel {
          inherit name;
          inherit (model) source hash;
        };
        org = head (splitString "/" model.source.huggingface.repo);
        modelName = last (splitString "/" model.source.huggingface.repo);
      in ''
        $DRY_RUN_CMD ln -sfn ${modelDrv} ~/.cache/huggingface/hub/models--${org}--${modelName}
      '') (attrNames cfg.models)}
    '';

    # Offline mode environment
    home.sessionVariables = mkIf cfg.offlineMode {
      HF_HUB_OFFLINE = "1";
      TRANSFORMERS_OFFLINE = "1";
    };
  };
}
```

---

## 12. CLI Tool

### 12.1 CLI Design

```
nix-model-repo - Nix Model Repo Manager

USAGE:
    nix-model-repo <COMMAND> [OPTIONS]

COMMANDS:
    prefetch    Download a model and print its hash
    list        List cached models
    info        Show model information
    gc          Manage garbage collection roots
    verify      Verify model integrity

EXAMPLES:
    # Get hash for a new model
    nix-model-repo prefetch huggingface:meta-llama/Llama-2-7b-hf

    # List cached models
    nix-model-repo list

    # Pin a model to prevent garbage collection
    nix-model-repo gc pin llama-2-7b

    # Verify model hasn't changed upstream
    nix-model-repo verify llama-2-7b
```

### 12.2 CLI Implementation

```bash
#!/usr/bin/env bash
# cli/nix-model-repo.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

usage() {
    cat << 'EOF'
nix-model-repo - Nix Model Repo Manager

USAGE:
    nix-model-repo <COMMAND> [OPTIONS]

COMMANDS:
    prefetch <source:repo>      Download model and print hash
    list                        List cached models
    info <model>                Show model information
    gc pin <model>              Create GC root for model
    gc unpin <model>            Remove GC root
    verify <model>              Verify model integrity

OPTIONS:
    -h, --help                  Show this help
    -v, --verbose               Verbose output

EXAMPLES:
    nix-model-repo prefetch huggingface:meta-llama/Llama-2-7b-hf
    nix-model-repo prefetch huggingface:microsoft/phi-2@main
    nix-model-repo list
    nix-model-repo gc pin llama-2-7b
EOF
}

cmd_prefetch() {
    local spec="$1"

    # Parse source:repo@rev format
    local source repo rev
    IFS=':' read -r source repo <<< "$spec"

    if [[ "$repo" == *"@"* ]]; then
        IFS='@' read -r repo rev <<< "$repo"
    else
        rev="main"
    fi

    echo -e "${YELLOW}Prefetching: $source:$repo@$rev${NC}"

    # Use nix-prefetch with fake hash to get real hash
    local result
    result=$(nix build --impure --expr "
      let
        flake = builtins.getFlake \"github:parthspatel/nix-model-repo\";
        pkgs = import <nixpkgs> {};
      in
        flake.lib.fetchModel {
          name = \"prefetch-temp\";
          source.$source.repo = \"$repo\";
          source.$source.revision = \"$rev\";
          hash = \"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\";
        }
    " 2>&1 || true)

    # Extract real hash from error
    local hash
    hash=$(echo "$result" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+')

    if [[ -n "$hash" ]]; then
        echo -e "${GREEN}Hash: $hash${NC}"
        echo ""
        echo "Add to your flake.nix:"
        echo ""
        echo "  $repo = fetchModel {"
        echo "    source.$source.repo = \"$repo\";"
        echo "    hash = \"$hash\";"
        echo "  };"
    else
        echo -e "${RED}Failed to prefetch model${NC}"
        echo "$result"
        exit 1
    fi
}

cmd_list() {
    echo "Cached AI models in Nix store:"
    echo ""

    # Find models by metadata file
    find /nix/store -maxdepth 2 -name ".nix-model-repo-meta.json" 2>/dev/null | while read -r meta; do
        local dir
        dir=$(dirname "$meta")
        local name
        name=$(basename "$dir")

        local source
        source=$(jq -r '.source // "unknown"' "$meta")

        printf "  %-40s %s\n" "$name" "$source"
    done
}

cmd_info() {
    local model="$1"

    # Find model in store
    local path
    path=$(find /nix/store -maxdepth 1 -name "*$model*" -type d | head -1)

    if [[ -z "$path" ]]; then
        echo -e "${RED}Model not found: $model${NC}"
        exit 1
    fi

    local meta="$path/.nix-model-repo-meta.json"
    if [[ -f "$meta" ]]; then
        echo "Model: $model"
        echo "Path: $path"
        echo ""
        jq . "$meta"
    else
        echo -e "${YELLOW}No metadata found for: $model${NC}"
    fi
}

cmd_gc() {
    local action="$1"
    local model="$2"
    local gc_root_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nix-model-repo/gc-roots"

    mkdir -p "$gc_root_dir"

    case "$action" in
        pin)
            local path
            path=$(find /nix/store -maxdepth 1 -name "*$model*" -type d | head -1)
            if [[ -z "$path" ]]; then
                echo -e "${RED}Model not found: $model${NC}"
                exit 1
            fi
            nix-store --add-root "$gc_root_dir/$model" --indirect -r "$path"
            echo -e "${GREEN}Pinned: $model${NC}"
            ;;
        unpin)
            rm -f "$gc_root_dir/$model"
            echo -e "${GREEN}Unpinned: $model${NC}"
            ;;
        *)
            echo "Usage: nix-model-repo gc [pin|unpin] <model>"
            exit 1
            ;;
    esac
}

# Main
case "${1:-}" in
    prefetch)
        shift
        cmd_prefetch "$@"
        ;;
    list)
        cmd_list
        ;;
    info)
        shift
        cmd_info "$@"
        ;;
    gc)
        shift
        cmd_gc "$@"
        ;;
    -h|--help|"")
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
```

---

## 13. Error Handling

### 13.1 Error Categories

| Category           | Example                         | Handling                                    |
| ------------------ | ------------------------------- | ------------------------------------------- |
| Network errors     | Connection timeout, DNS failure | Retry with backoff                          |
| Auth errors        | 401, 403, expired token         | Helpful error message with fix instructions |
| Hash mismatch      | Model changed upstream          | Fail with current vs expected hash          |
| Validation failure | modelscan finds malware         | Abort with scan results                     |
| Disk space         | Not enough space for model      | Pre-check with size estimate                |
| Rate limiting      | 429 Too Many Requests           | Wait and retry, respect Retry-After         |

### 13.2 Error Message Format

```
error: Failed to fetch model: meta-llama/Llama-2-7b-hf

  ┌─ Source: huggingface
  │  Repo:   meta-llama/Llama-2-7b-hf
  │  Rev:    main
  │
  ✗ Error: HTTP 403 Forbidden
  │
  │ This is a gated model requiring license acceptance.
  │
  │ To fix this:
  │   1. Visit https://huggingface.co/meta-llama/Llama-2-7b-hf
  │   2. Click "Access repository" and accept the license
  │   3. Generate a token at https://huggingface.co/settings/tokens
  │   4. Set the token:
  │      export HF_TOKEN=your_token_here
  │   5. Retry the build
  │
  └─ For more help: https://github.com/parthspatel/nix-model-repo/wiki/Gated-Models
```

### 13.3 Error Handling Implementation

```bash
# fetchers/common.sh - Error handling utilities

# Structured error output
error_exit() {
    local source="$1"
    local error_type="$2"
    local message="$3"
    local help_url="${4:-}"

    cat >&2 << EOF

error: Failed to fetch model

  ┌─ Source: $source
  │
  ✗ Error: $error_type
  │
  │ $message
  │
EOF

    if [[ -n "$help_url" ]]; then
        echo "  └─ For more help: $help_url" >&2
    fi

    exit 1
}

# HTTP error handling
handle_http_error() {
    local code="$1"
    local url="$2"
    local source="$3"

    case "$code" in
        401)
            error_exit "$source" "HTTP 401 Unauthorized" \
                "Authentication required. Set HF_TOKEN environment variable." \
                "https://huggingface.co/settings/tokens"
            ;;
        403)
            if [[ "$source" == "huggingface" ]]; then
                error_exit "$source" "HTTP 403 Forbidden" \
                    "This may be a gated model requiring license acceptance.

  To fix this:
    1. Visit the model page on HuggingFace
    2. Click 'Access repository' and accept the license
    3. Set HF_TOKEN with a valid access token"
            else
                error_exit "$source" "HTTP 403 Forbidden" \
                    "Access denied. Check your credentials."
            fi
            ;;
        404)
            error_exit "$source" "HTTP 404 Not Found" \
                "Model or file not found. Check the repository name and revision."
            ;;
        429)
            # Rate limited - this should trigger retry logic
            return 1
            ;;
        5*)
            error_exit "$source" "HTTP $code Server Error" \
                "The server is experiencing issues. Try again later."
            ;;
        *)
            error_exit "$source" "HTTP $code" \
                "Unexpected HTTP error when fetching: $url"
            ;;
    esac
}
```

---

## 14. Configuration Schema

### 14.1 Full Configuration Example

```nix
{
  # Basic example
  simple = fetchModel {
    name = "llama-2-7b";
    source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
    hash = "sha256-abc123...";
  };

  # Full configuration
  complete = fetchModel {
    name = "llama-2-7b-secure";

    # Source configuration
    source = {
      huggingface = {
        repo = "meta-llama/Llama-2-7b-hf";
        revision = "main";
        files = [ "*.safetensors" "config.json" "tokenizer*" ];
      };
    };

    # Hash (required for reproducibility)
    hash = "sha256-abc123...";

    # Validation
    validation = {
      enable = true;
      validators = [
        {
          name = "custom-check";
          command = "${./my-validator.sh} $src";
          onFailure = "warn";
        }
      ];
      skipDefaults = false;  # Still run modelscan, pickle-scan
    };

    # Integration
    integration = {
      huggingface = {
        enable = true;
        org = "meta-llama";       # Override if different from repo
        model = "Llama-2-7b-hf";
      };
      environment = {
        LLAMA_MODEL_PATH = "$out";
      };
    };

    # Network configuration
    network = {
      bandwidth.limit = "50M";
      timeout = {
        connect = 30;
        read = 300;
      };
      retry = {
        maxAttempts = 3;
        baseDelay = 2;
      };
      proxy = null;  # Or { http = "..."; https = "..."; }
    };

    # Authentication
    auth = {
      tokenEnvVar = "HF_TOKEN";
      # OR
      tokenFile = "/run/secrets/hf-token";
    };

    # Failure handling
    onFailure = {
      action = "clean";  # clean | persist | retry
      notify = null;     # Optional notification script
    };

    # Standard Nix meta
    meta = {
      description = "Llama 2 7B language model";
      license = lib.licenses.llama2;
      platforms = lib.platforms.all;
    };
  };
}
```

### 14.2 Configuration Type Hierarchy

```
fetchModel
├── name: string (required)
├── source: SourceConfig (required, exactly one)
│   ├── huggingface: HuggingFaceSource
│   ├── git-lfs: GitLfsSource
│   ├── git-xet: GitXetSource
│   ├── s3: S3Source
│   ├── url: UrlSource
│   ├── ollama: OllamaSource
│   └── mlflow: MlflowSource
├── hash: string (required)
├── validation: ValidationConfig
│   ├── enable: bool (default: true)
│   ├── validators: [ValidatorSpec]
│   ├── skipDefaults: bool (default: false)
│   └── onFailure: "abort" | "warn" | "skip"
├── integration: IntegrationConfig
│   ├── huggingface: HfIntegration
│   │   ├── enable: bool
│   │   ├── org: string?
│   │   └── model: string?
│   └── environment: { string: string }
├── network: NetworkConfig
│   ├── bandwidth: { limit: string? }
│   ├── timeout: { connect: int, read: int }
│   ├── retry: { maxAttempts: int, baseDelay: int }
│   └── proxy: { http: string?, https: string? }?
├── auth: AuthConfig
│   ├── tokenEnvVar: string?
│   └── tokenFile: path?
├── onFailure: FailureConfig
│   ├── action: "clean" | "persist" | "retry"
│   └── notify: string?
└── meta: NixMeta
```

---

## 15. Validation Presets & Patterns

### 15.1 Validation Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         VALIDATION PIPELINE                                  │
│                                                                              │
│  Phase 1: FOD Fetch                 Phase 2: Validation                      │
│  ───────────────────                ──────────────────                       │
│  ┌─────────────────┐               ┌─────────────────┐                      │
│  │ Download files  │               │ Security scans  │                      │
│  │ (network)       │──────────────▶│ Custom hooks    │                      │
│  │                 │               │ (no network)    │                      │
│  └─────────────────┘               └─────────────────┘                      │
│         │                                   │                                │
│         ▼                                   ▼                                │
│  Hash verified by Nix               Validators execute                       │
│  (FOD guarantee)                    (can fail build)                         │
│                                                                              │
│  Output: rawModels.x.y              Output: models.x.y                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 15.2 Built-in Validation Presets

```nix
# lib/validation/presets.nix

{
  # Preset: Strict (production deployments)
  strict = {
    enable = true;
    defaults = {
      modelscan = true;      # Scan for malicious serialized objects
      pickleScan = true;     # Scan pickle files for dangerous ops
      checksums = true;      # Verify file integrity
    };
    validators = [
      validators.noPickleFiles
      validators.safetensorsOnly
      validators.licenseCheck
    ];
    onFailure = "abort";
    timeout = 600;  # 10 minutes for large models
  };

  # Preset: Standard (default for most use cases)
  standard = {
    enable = true;
    defaults = {
      modelscan = true;
      pickleScan = true;
      checksums = true;
    };
    validators = [];
    onFailure = "abort";
    timeout = 300;
  };

  # Preset: Minimal (CI/testing, faster builds)
  minimal = {
    enable = true;
    defaults = {
      modelscan = false;
      pickleScan = false;
      checksums = true;  # Always verify integrity
    };
    validators = [];
    onFailure = "warn";
    timeout = 60;
  };

  # Preset: None (raw data only, skip all validation)
  none = {
    enable = false;
  };

  # Preset: Paranoid (maximum security)
  paranoid = {
    enable = true;
    defaults = {
      modelscan = true;
      pickleScan = true;
      checksums = true;
    };
    validators = [
      validators.noPickleFiles
      validators.safetensorsOnly
      validators.noPythonCode
      validators.maxSize "50G"
      validators.licenseCheck
      validators.signatureVerify
    ];
    onFailure = "abort";
    timeout = 1200;
  };
}
```

### 15.3 Built-in Validators

```nix
# lib/validation/validators.nix

{
  # Reject pickle files entirely
  noPickleFiles = {
    name = "no-pickle";
    description = "Ensure no pickle files are present";
    command = ''
      shopt -s nullglob globstar
      pickles=($src/**/*.pkl $src/**/*.pickle)
      if [[ ''${#pickles[@]} -gt 0 ]]; then
        echo "ERROR: Pickle files detected:" >&2
        printf '  %s\n' "''${pickles[@]}" >&2
        echo "Use safetensors format instead for security." >&2
        exit 1
      fi
    '';
    onFailure = "abort";
  };

  # Require safetensors format for weights
  safetensorsOnly = {
    name = "safetensors-only";
    description = "Ensure model uses safetensors format";
    command = ''
      shopt -s nullglob
      # Check for unsafe weight formats
      unsafe=($(find $src -name "*.bin" -o -name "*.pt" -o -name "*.pth" 2>/dev/null))
      if [[ ''${#unsafe[@]} -gt 0 ]]; then
        echo "ERROR: Non-safetensors weights found:" >&2
        printf '  %s\n' "''${unsafe[@]}" >&2
        exit 1
      fi
      # Ensure safetensors exist
      safetensors=($(find $src -name "*.safetensors" 2>/dev/null))
      if [[ ''${#safetensors[@]} -eq 0 ]]; then
        echo "WARNING: No safetensors files found" >&2
      fi
    '';
    onFailure = "abort";
  };

  # Enforce maximum model size
  maxSize = limit: {
    name = "max-size-${limit}";
    description = "Ensure model size is under ${limit}";
    command = ''
      limit_bytes=$(numfmt --from=iec ${limit})
      actual_bytes=$(du -sb $src | cut -f1)
      if [[ $actual_bytes -gt $limit_bytes ]]; then
        actual_human=$(numfmt --to=iec $actual_bytes)
        echo "ERROR: Model size $actual_human exceeds limit ${limit}" >&2
        exit 1
      fi
    '';
    onFailure = "abort";
  };

  # Verify required files exist
  requiredFiles = files: {
    name = "required-files";
    description = "Verify required files are present";
    command = lib.concatMapStrings (f: ''
      if [[ ! -f "$src/${f}" ]]; then
        echo "ERROR: Required file missing: ${f}" >&2
        exit 1
      fi
    '') files;
    onFailure = "abort";
  };

  # Reject Python code in model
  noPythonCode = {
    name = "no-python-code";
    description = "Ensure no Python code is bundled";
    command = ''
      shopt -s nullglob globstar
      pyfiles=($src/**/*.py $src/**/*.pyc $src/**/*.pyo)
      if [[ ''${#pyfiles[@]} -gt 0 ]]; then
        echo "ERROR: Python code found in model:" >&2
        printf '  %s\n' "''${pyfiles[@]}" >&2
        exit 1
      fi
    '';
    onFailure = "abort";
  };

  # Check license compatibility
  licenseCheck = {
    name = "license-check";
    description = "Verify license is acceptable";
    command = ''
      if [[ -f "$src/LICENSE" ]] || [[ -f "$src/LICENSE.md" ]] || [[ -f "$src/LICENSE.txt" ]]; then
        echo "License file found"
        # Could add license parsing logic here
      else
        echo "WARNING: No license file found" >&2
      fi
    '';
    onFailure = "warn";
  };

  # Verify cryptographic signatures (if available)
  signatureVerify = {
    name = "signature-verify";
    description = "Verify model signatures if present";
    command = ''
      if [[ -f "$src/.signatures.json" ]]; then
        echo "Signature file found, verifying..."
        # Signature verification logic
      else
        echo "No signature file found, skipping verification"
      fi
    '';
    onFailure = "warn";
  };

  # Custom inline validator
  custom = { name, script, onFailure ? "abort" }: {
    inherit name onFailure;
    description = "Custom validator: ${name}";
    command = script;
  };
}
```

### 15.4 User Experience: Validation

```nix
let
  fetchModel = nix-model-repo.lib.fetchModel pkgs;
  presets = nix-model-repo.lib.validation.presets;
  validators = nix-model-repo.lib.validation.validators;
in {
  # Use a preset directly
  prod-model = fetchModel {
    name = "mistral-prod";
    source.huggingface.repo = "mistralai/Mistral-7B-v0.1";
    hash = "sha256-abc...";
    validation = presets.strict;
  };

  # Extend a preset with additional validators
  custom-validated = fetchModel {
    name = "my-model";
    source.huggingface.repo = "my-org/my-model";
    hash = "sha256-def...";
    validation = presets.standard // {
      validators = presets.standard.validators ++ [
        (validators.maxSize "10G")
        (validators.requiredFiles [ "config.json" "tokenizer.json" ])
        (validators.custom {
          name = "check-vocab-size";
          script = ''
            vocab_size=$(jq '.vocab_size' $src/config.json)
            if [[ $vocab_size -gt 100000 ]]; then
              echo "WARNING: Large vocabulary size: $vocab_size" >&2
            fi
          '';
          onFailure = "warn";
        })
      ];
    };
  };

  # Skip validation entirely (CI/testing)
  ci-model = fetchModel {
    name = "test-model";
    source.huggingface.repo = "my-org/my-model";
    hash = "sha256-def...";
    validation = presets.none;
  };

  # Minimal validation for faster builds
  dev-model = fetchModel {
    name = "dev-model";
    source.huggingface.repo = "my-org/my-model";
    hash = "sha256-ghi...";
    validation = presets.minimal;
  };

  # Maximum security for production
  secure-model = fetchModel {
    name = "secure-model";
    source.huggingface.repo = "my-org/my-model";
    hash = "sha256-jkl...";
    validation = presets.paranoid;
  };
}
```

### 15.5 Validation Configuration Reference

```nix
validation = {
  # Master switch - disable all validation
  enable = true;  # default: true

  # Built-in security scanners
  defaults = {
    modelscan = true;     # Scan for malicious serialized objects
    pickleScan = true;    # Scan pickle files for code execution
    checksums = true;     # Verify file integrity
  };

  # Additional validators (run after defaults)
  validators = [
    {
      name = "my-validator";
      description = "Optional description";
      command = "script to run with $src available";
      onFailure = "abort";  # abort | warn | skip
      timeout = 300;        # seconds
    }
  ];

  # Skip built-in validators
  skipDefaults = false;

  # Global failure handling
  onFailure = "abort";  # abort | warn | skip

  # Global timeout for all validators
  timeout = 300;
};
```

---

## 16. Source Reuse Patterns

### 16.1 Source Factory Pattern

Define reusable source templates for your infrastructure:

```nix
# In your flake.nix or a shared module
let
  # Factory for your company's MLFlow server
  mkMlflowSource = { modelName, version ? null, stage ? null }: {
    mlflow = {
      trackingUri = "https://mlflow.mycompany.com";
      inherit modelName;
      modelVersion = version;
      modelStage = stage;
    };
  };

  # Factory for your S3 model bucket
  mkS3Source = { prefix, files ? null }: {
    s3 = {
      bucket = "mycompany-model-repo";
      region = "us-west-2";
      inherit prefix files;
    };
  };

  # Factory for your Git-Xet repository
  mkXetSource = { repo, rev, files ? null }: {
    git-xet = {
      url = "https://github.com/mycompany/${repo}";
      inherit rev files;
      xet.endpoint = "https://xethub.mycompany.com";
    };
  };

  # Factory for HuggingFace org
  mkHfSource = { model, revision ? "main", files ? null }: {
    huggingface = {
      repo = "mycompany/${model}";
      inherit revision files;
    };
  };

  fetchModel = nix-model-repo.lib.fetchModel pkgs;
in {
  # Now use factories - minimal config per model
  packages.${system} = {
    # MLFlow models
    sft-v1 = fetchModel {
      name = "sft-v1";
      source = mkMlflowSource { modelName = "mistral-sft"; version = "1"; };
      hash = "sha256-aaa...";
    };

    sft-v2 = fetchModel {
      name = "sft-v2";
      source = mkMlflowSource { modelName = "mistral-sft"; version = "2"; };
      hash = "sha256-bbb...";
    };

    sft-prod = fetchModel {
      name = "sft-prod";
      source = mkMlflowSource { modelName = "mistral-sft"; stage = "Production"; };
      hash = "sha256-ccc...";
    };

    # S3 models
    embeddings = fetchModel {
      name = "embeddings";
      source = mkS3Source { prefix = "embeddings/v3"; };
      hash = "sha256-ddd...";
    };

    # Git-Xet models
    llm-experimental = fetchModel {
      name = "llm-experimental";
      source = mkXetSource { repo = "llm-models"; rev = "abc123"; };
      hash = "sha256-eee...";
    };
  };
}
```

### 16.2 Library-Provided Source Factories

```nix
# lib/sources/factories.nix - We provide common factories

{
  # HuggingFace organization factories
  huggingface = {
    # Pre-configured for major orgs
    metaLlama = model: {
      huggingface.repo = "meta-llama/${model}";
    };

    mistralai = model: {
      huggingface.repo = "mistralai/${model}";
    };

    microsoft = model: {
      huggingface.repo = "microsoft/${model}";
    };

    google = model: {
      huggingface.repo = "google/${model}";
    };

    # Generic org factory
    org = orgName: model: {
      huggingface.repo = "${orgName}/${model}";
    };
  };

  # Ollama model factory
  ollama = {
    model = name: {
      ollama.model = name;
    };
  };

  # User-definable factories
  mkMlflow = { trackingUri }: { modelName, version ? null, stage ? null }: {
    mlflow = {
      inherit trackingUri modelName;
      modelVersion = version;
      modelStage = stage;
    };
  };

  mkS3 = { bucket, region }: { prefix, files ? null }: {
    s3 = {
      inherit bucket region prefix files;
    };
  };

  mkGitLfs = { baseUrl }: { repo, rev, files ? null }: {
    git-lfs = {
      url = "${baseUrl}/${repo}";
      inherit rev;
      lfsFiles = files;
    };
  };

  mkGitXet = { endpoint }: { url, rev, files ? null }: {
    git-xet = {
      inherit url rev files;
      xet = { inherit endpoint; };
    };
  };

  mkHttp = { baseUrl }: { path, filename ? null }: {
    url = {
      urls = [{
        url = "${baseUrl}/${path}";
        inherit filename;
      }];
    };
  };
}
```

### 16.3 User Experience: Source Factories

```nix
let
  fetchModel = nix-model-repo.lib.fetchModel pkgs;
  sources = nix-model-repo.lib.sources;

  # Create company-specific factories
  myMlflow = sources.mkMlflow {
    trackingUri = "https://mlflow.mycompany.com";
  };

  myS3 = sources.mkS3 {
    bucket = "mycompany-models";
    region = "us-west-2";
  };

  myXet = sources.mkGitXet {
    endpoint = "https://xethub.mycompany.com";
  };
in {
  packages.${system} = {
    # Use built-in HuggingFace factories
    llama = fetchModel {
      name = "llama-2-7b";
      source = sources.huggingface.metaLlama "Llama-2-7b-hf";
      hash = "sha256-aaa...";
    };

    mistral = fetchModel {
      name = "mistral-7b";
      source = sources.huggingface.mistralai "Mistral-7B-v0.1";
      hash = "sha256-bbb...";
    };

    phi = fetchModel {
      name = "phi-2";
      source = sources.huggingface.microsoft "phi-2";
      hash = "sha256-ccc...";
    };

    # Use custom MLFlow factory
    sft-prod = fetchModel {
      name = "sft-prod";
      source = myMlflow { modelName = "mistral-sft"; stage = "Production"; };
      hash = "sha256-ddd...";
    };

    sft-staging = fetchModel {
      name = "sft-staging";
      source = myMlflow { modelName = "mistral-sft"; stage = "Staging"; };
      hash = "sha256-eee...";
    };

    # Use custom S3 factory
    embeddings-v2 = fetchModel {
      name = "embeddings-v2";
      source = myS3 { prefix = "embeddings/v2"; };
      hash = "sha256-fff...";
    };

    embeddings-v3 = fetchModel {
      name = "embeddings-v3";
      source = myS3 { prefix = "embeddings/v3"; };
      hash = "sha256-ggg...";
    };

    # Use Ollama factory
    llama-quantized = fetchModel {
      name = "llama-quantized";
      source = sources.ollama.model "llama2:7b-q4_0";
      hash = "sha256-hhh...";
    };
  };
}
```

### 16.4 Full Model Definition Reuse

For complete model configurations, not just sources:

```nix
let
  fetchModel = nix-model-repo.lib.fetchModel pkgs;
  presets = nix-model-repo.lib.validation.presets;
  sources = nix-model-repo.lib.sources;

  # Base configuration shared across models
  baseConfig = {
    validation = presets.standard;
    integration.huggingface.enable = true;
    network = {
      timeout.connect = 30;
      timeout.read = 600;
      retry.maxAttempts = 3;
    };
  };

  # Production config - stricter validation
  prodConfig = baseConfig // {
    validation = presets.strict;
  };

  # Development config - faster builds
  devConfig = baseConfig // {
    validation = presets.minimal;
  };

  # Helper to apply defaults
  withDefaults = config: model: config // model;
  withProdDefaults = withDefaults prodConfig;
  withDevDefaults = withDefaults devConfig;

in {
  packages.${system} = {
    # Production models with strict validation
    mistral-prod = fetchModel (withProdDefaults {
      name = "mistral-prod";
      source = sources.huggingface.mistralai "Mistral-7B-v0.1";
      hash = "sha256-aaa...";
    });

    llama-prod = fetchModel (withProdDefaults {
      name = "llama-prod";
      source = sources.huggingface.metaLlama "Llama-2-7b-hf";
      hash = "sha256-bbb...";
    });

    # Development models with minimal validation
    mistral-dev = fetchModel (withDevDefaults {
      name = "mistral-dev";
      source = sources.huggingface.mistralai "Mistral-7B-v0.1";
      hash = "sha256-aaa...";  # Same model, different validation
    });
  };
}
```

### 16.5 Multi-Source Model Variants

Same model from different sources:

```nix
let
  fetchModel = nix-model-repo.lib.fetchModel pkgs;
  sources = nix-model-repo.lib.sources;

  # Define model variants
  mistral7b = {
    # Original from HuggingFace
    hf = fetchModel {
      name = "mistral-7b-hf";
      source = sources.huggingface.mistralai "Mistral-7B-v0.1";
      hash = "sha256-aaa...";
    };

    # Quantized from Ollama
    ollama = fetchModel {
      name = "mistral-7b-ollama";
      source = sources.ollama.model "mistral:7b";
      hash = "sha256-bbb...";
    };

    # Mirror from company Git-Xet
    xet = fetchModel {
      name = "mistral-7b-xet";
      source.git-xet = {
        url = "https://github.com/mycompany/model-mirrors";
        rev = "abc123";
        files = [ "mistral-7b/*" ];
        xet.endpoint = "https://xethub.mycompany.com";
      };
      hash = "sha256-ccc...";
    };

    # From company S3 (for air-gapped deployments)
    s3 = fetchModel {
      name = "mistral-7b-s3";
      source.s3 = {
        bucket = "mycompany-models";
        prefix = "mistral/7b-v0.1";
        region = "us-west-2";
      };
      hash = "sha256-ddd...";
    };
  };
in {
  packages.${system} = {
    # Expose all variants
    inherit (mistral7b) hf ollama xet s3;

    # Or use default
    mistral = mistral7b.hf;
  };
}
```

---

## 17. Flake Structure & Exports

### 17.1 Complete Flake Structure

```nix
# flake.nix
{
  description = "Nix Model Repo Manager - Reproducible AI/ML model management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
  let
    # Systems we support
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    # Import library (system-agnostic)
    lib = import ./lib { inherit (nixpkgs) lib; };

  in {
    #
    # SYSTEM-AGNOSTIC EXPORTS
    #

    # Core library - user passes pkgs
    lib = {
      # Main function
      fetchModel = pkgs: config: import ./lib/fetchModel.nix {
        inherit pkgs config;
        inherit (nixpkgs) lib;
      };

      # Source factories
      sources = import ./lib/sources/factories.nix { inherit (nixpkgs) lib; };

      # Validation presets and validators
      validation = {
        presets = import ./lib/validation/presets.nix { inherit (nixpkgs) lib; };
        validators = import ./lib/validation/validators.nix { inherit (nixpkgs) lib; };
        mkValidator = import ./lib/validation/mk-validator.nix { inherit (nixpkgs) lib; };
      };

      # Integration helpers
      integration = import ./lib/integration.nix { inherit (nixpkgs) lib; };

      # Utilities
      prefetchModel = pkgs: spec: import ./lib/utils/prefetch.nix {
        inherit pkgs spec;
        inherit (nixpkgs) lib;
      };

      # Instantiate model definitions with pkgs
      instantiate = pkgs: defs:
        nixpkgs.lib.mapAttrsRecursive
          (path: def: self.lib.fetchModel pkgs def)
          defs;

      # Create shell hook for HF cache setup
      mkShellHook = pkgs: { models }: import ./lib/integration/shell-hook.nix {
        inherit pkgs models;
        inherit (nixpkgs) lib;
      };
    };

    # Model definitions (system-agnostic configs, no derivations)
    modelDefs = import ./models/definitions.nix { inherit (nixpkgs) lib; };

    # NixOS module
    nixosModules.default = import ./modules/nixos.nix;
    nixosModules.model-repo = self.nixosModules.default;

    # Home Manager module
    homeManagerModules.default = import ./modules/home-manager.nix;
    homeManagerModules.model-repo = self.homeManagerModules.default;

    # Overlay for pkgs integration
    overlays.default = final: prev: {
      fetchAiModel = self.lib.fetchModel final;
      aiModelSources = self.lib.sources;
      aiModelValidation = self.lib.validation;
    };

  } // flake-utils.lib.eachSystem supportedSystems (system:
  let
    pkgs = nixpkgs.legacyPackages.${system};

    # Instantiate model definitions for this system
    instantiatedModels = self.lib.instantiate pkgs self.modelDefs;

  in {
    #
    # PER-SYSTEM EXPORTS
    #

    # Pre-built models from registry (validated)
    models = instantiatedModels;

    # Raw models (no validation, for CI/testing)
    rawModels = self.lib.instantiate pkgs (
      nixpkgs.lib.mapAttrsRecursive
        (path: def: def // { validation.enable = false; })
        self.modelDefs
    );

    # CLI tool
    packages = {
      default = self.packages.${system}.nix-model-repo;
      nix-model-repo = pkgs.callPackage ./cli { };
    };

    # Development shell
    devShells.default = pkgs.mkShell {
      packages = [
        self.packages.${system}.nix-model-repo
        pkgs.jq
        pkgs.curl
      ];
    };

    # Checks (tests)
    checks = import ./tests {
      inherit pkgs;
      lib = self.lib;
    };
  });
}
```

### 17.2 Library Exports Summary

| Export                       | Type                           | Description                                 |
| ---------------------------- | ------------------------------ | ------------------------------------------- |
| `lib.fetchModel`             | `pkgs -> config -> derivation` | Core function, user passes pkgs             |
| `lib.sources`                | `attrset`                      | Source factories (mkMlflow, mkS3, etc.)     |
| `lib.validation.presets`     | `attrset`                      | Validation presets (strict, standard, etc.) |
| `lib.validation.validators`  | `attrset`                      | Built-in validators                         |
| `lib.validation.mkValidator` | `config -> validator`          | Create custom validators                    |
| `lib.instantiate`            | `pkgs -> defs -> models`       | Bulk instantiate definitions                |
| `lib.mkShellHook`            | `pkgs -> config -> string`     | Generate shell hook for HF cache            |
| `modelDefs`                  | `attrset`                      | System-agnostic model definitions           |
| `models.${system}`           | `attrset`                      | Pre-built validated models                  |
| `rawModels.${system}`        | `attrset`                      | Pre-built models without validation         |
| `nixosModules.default`       | `module`                       | NixOS integration                           |
| `homeManagerModules.default` | `module`                       | Home Manager integration                    |
| `overlays.default`           | `overlay`                      | Nixpkgs overlay                             |

### 17.3 End-User Flake Example

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { self, nixpkgs, nix-model-repo, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    # Access library
    fetchModel = nix-model-repo.lib.fetchModel pkgs;
    sources = nix-model-repo.lib.sources;
    presets = nix-model-repo.lib.validation.presets;
    validators = nix-model-repo.lib.validation.validators;

    # Access pre-built registry
    models = nix-model-repo.models.${system};

    # Create custom source factories
    myMlflow = sources.mkMlflow {
      trackingUri = "https://mlflow.mycompany.com";
    };

  in {
    packages.${system} = {
      # From registry
      llama = models.meta-llama.llama-2-7b;
      mistral = models.mistralai.mistral-7b;

      # Custom fetch with factory
      sft-prod = fetchModel {
        name = "sft-prod";
        source = myMlflow { modelName = "mistral-sft"; stage = "Production"; };
        hash = "sha256-abc...";
        validation = presets.strict;
      };

      # Custom fetch with inline source
      my-model = fetchModel {
        name = "my-model";
        source.huggingface = {
          repo = "my-org/my-model";
          revision = "v1.0";
          files = [ "*.safetensors" "config.json" ];
        };
        hash = "sha256-def...";
        validation = presets.standard // {
          validators = [
            (validators.maxSize "20G")
            (validators.requiredFiles [ "config.json" ])
          ];
        };
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      packages = [
        self.packages.${system}.llama
        self.packages.${system}.mistral
      ];

      shellHook = nix-model-repo.lib.mkShellHook pkgs {
        models = [
          { drv = self.packages.${system}.llama; org = "meta-llama"; model = "Llama-2-7b-hf"; }
          { drv = self.packages.${system}.mistral; org = "mistralai"; model = "Mistral-7B-v0.1"; }
        ];
      };
    };
  };
}
```

---

## Next Steps

1. **Implement Core Library** (`lib/fetchModel.nix`, `lib/sources/*.nix`)
2. **Write HuggingFace Fetcher** (`fetchers/huggingface.sh`)
3. **Create Validation Framework** (`lib/validation/*.nix`)
4. **Build CLI Tool** (`cli/nix-model-repo.sh`)
5. **Create Test Suite** (unit tests for Nix functions)
6. **Add NixOS Module** (`modules/nixos.nix`)
7. **Write Documentation** (`docs/USAGE.md`)
