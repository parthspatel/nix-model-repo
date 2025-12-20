# Architecture

This document describes the architecture of Nix AI Models.

## Overview

Nix AI Models is designed around the principle of reproducible, secure model fetching using Nix's Fixed Output Derivation (FOD) system.

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Configuration                        │
│  fetchModel { name, source, hash, validation, ... }             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Type Validation                             │
│  • Validate config structure                                     │
│  • Normalize source config                                       │
│  • Apply defaults                                                │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Source Adapter Dispatch                       │
│  • Select appropriate adapter (HF, S3, MLflow, etc.)            │
│  • Generate FOD derivation                                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                Phase 1: Fixed Output Derivation                  │
│  • Network access allowed                                        │
│  • Download model files                                          │
│  • Create HuggingFace cache structure                           │
│  • Hash verification (SHA256)                                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Phase 2: Validation                            │
│  • No network access                                             │
│  • Security scanning (modelscan)                                 │
│  • Custom validators                                             │
│  • Pickle file detection                                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Final Derivation                            │
│  • Validated model in Nix store                                  │
│  • HuggingFace-compatible structure                             │
│  • Metadata (passthru)                                          │
└─────────────────────────────────────────────────────────────────┘
```

## Core Concepts

### Fixed Output Derivations (FODs)

FODs are Nix derivations where the output hash is known in advance. They're the only derivation type allowed to access the network during build.

**Key properties:**
- Output hash must be specified upfront
- Network access is allowed
- Build is considered successful only if output matches expected hash
- Results are cached and shared across machines

### Two-Phase Architecture

We split fetching and validation into two phases:

**Phase 1: Fetch (FOD)**
- Downloads model files
- Creates proper directory structure
- Must be deterministic (same hash every time)
- Network access allowed

**Phase 2: Validate (Regular Derivation)**
- Takes Phase 1 output as input
- Runs security scanners
- No network access
- Can use any tools

This separation allows:
- Hash verification before any validation
- Non-deterministic validators (different scan versions)
- Cached validation results
- Flexible validator configuration

### Source Adapter Pattern

Each source type (HuggingFace, S3, etc.) implements a common interface:

```nix
{
  # Unique identifier
  sourceType = "huggingface";

  # Create the FOD derivation
  mkFetchDerivation = { name, hash, sourceConfig, auth, network }: derivation;

  # Validate source configuration
  validateConfig = sourceConfig: { valid, errors };

  # Environment variables needed (passed through sandbox)
  impureEnvVars = auth: [ "HF_TOKEN" ];

  # Build dependencies
  buildInputs = pkgs: [ curl jq ];

  # Extract metadata from config
  extractMeta = sourceConfig: { org, model, ... };
}
```

## Component Details

### lib/fetchModel.nix

The main entry point that orchestrates the fetch process:

```nix
config:
let
  # 1. Validate and normalize config
  mergedConfig = types.mergeWithDefaults config;

  # 2. Select source adapter
  sourceAdapter = sources.dispatch mergedConfig.source;

  # 3. Create FOD (Phase 1)
  rawModel = sourceAdapter.mkFetchDerivation {
    inherit (mergedConfig) name hash;
    sourceConfig = mergedConfig.source;
    auth = mergedConfig.auth;
    network = mergedConfig.network;
  };

  # 4. Run validation (Phase 2)
  validatedModel = validation.mkValidationDerivation {
    src = rawModel;
    validators = mergedConfig.validation.validators;
  };

in validatedModel // {
  passthru = {
    raw = rawModel;  # Access unvalidated model
    meta = sourceAdapter.extractMeta mergedConfig.source;
  };
}
```

### lib/sources/

Source adapters handle the specifics of each source type:

```
lib/sources/
├── default.nix      # Dispatcher and registration
├── factories.nix    # Factory functions for DRY configs
├── huggingface.nix  # HuggingFace Hub
├── s3.nix           # AWS S3
├── mlflow.nix       # MLflow Registry
├── git-lfs.nix      # Git LFS
├── git-xet.nix      # Git-Xet
├── url.nix          # HTTP/HTTPS URLs
├── ollama.nix       # Ollama registry
└── mock.nix         # Testing mock
```

### lib/validation/

The validation framework:

```
lib/validation/
├── default.nix      # mkValidationDerivation
├── presets.nix      # Pre-configured validation sets
└── validators.nix   # Built-in validators
```

### fetchers/

Shell scripts that run during the FOD phase:

```
fetchers/
├── common.sh        # Shared utilities
└── huggingface.sh   # HuggingFace download logic
```

## Data Flow

### Configuration Flow

```
User Config → Type Validation → Default Merging → Source Selection → FOD Generation
```

### Build Flow

```
FOD Build → Hash Verify → Validation Build → Final Output
```

### Cache Structure

The output follows HuggingFace's cache format:

```
$out/
├── blobs/
│   ├── {sha256-hash-1}      # File contents
│   └── {sha256-hash-2}
├── refs/
│   └── main                 # Points to commit SHA
├── snapshots/
│   └── {commit-sha}/
│       ├── config.json → ../../blobs/{hash}
│       └── model.safetensors → ../../blobs/{hash}
└── .nix-ai-model-meta.json  # Metadata
```

## Extension Points

### Adding Sources

1. Create adapter in `lib/sources/`
2. Register in `lib/sources/default.nix`
3. Add type in `lib/types.nix`
4. Optionally add factory in `lib/sources/factories.nix`

### Adding Validators

1. Create validator using `mkValidator`
2. Export in `lib/validation/validators.nix`
3. Optionally add to presets

### Adding Integrations

1. Implement helper functions in `lib/integration.nix`
2. Update modules in `modules/`

## Security Model

### Trust Boundaries

1. **Source Trust**: User trusts the source (HuggingFace, S3, etc.)
2. **Hash Verification**: Nix verifies content hash
3. **Validation**: Security scanners check for known issues
4. **Nix Store**: Read-only, immutable storage

### Threat Mitigation

| Threat | Mitigation |
|--------|------------|
| Malicious model | Hash verification + validation |
| Supply chain attack | Pinned sources + hash |
| Pickle exploits | noPickleFiles validator |
| Network MITM | HTTPS + hash verification |

## Performance Considerations

### Caching

- FOD results are cached by hash
- Validation results are cached by input derivation
- Binary caches (Cachix, Attic) can serve pre-built models

### Large Models

- Use file filters to download only needed files
- Validation timeout is configurable
- Network timeout and retry settings available

### Parallel Builds

- Multiple models can build in parallel
- Nix handles dependency ordering automatically
