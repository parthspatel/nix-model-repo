# API Reference

This page documents the complete API for Nix Model Repo.

## Core Functions

### fetchModel

The primary function for fetching AI models.

**Signature:**

```nix
fetchModel :: Nixpkgs -> AttrSet -> Derivation
```

**Arguments:**

- `pkgs` - Nixpkgs instance to use for building.
- `config` - Configuration attribute set (see below).

**Returns:** A derivation containing the validated model with HuggingFace-compatible cache structure.

**Configuration Options:**

```nix
{
  # Required
  name = "model-name";           # Derivation name
  source = { ... };              # Source configuration
  hash = "sha256-...";           # Expected hash (SRI format)

  # Optional
  validation = { ... };          # Validation settings
  integration = { ... };         # Integration settings
  network = { ... };             # Network settings
  auth = { ... };                # Authentication
  meta = { ... };                # Nix meta attributes
}
```

**Example:**

```nix
let
  pkgs = import <nixpkgs> {};
  fetchModel = nix-model-repo.lib.fetchModel;
in
  fetchModel pkgs {
    name = "llama-2-7b";
    source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
    hash = "sha256-...";
  }
```

**Passthru Attributes:**

The returned derivation includes these passthru attributes:

```nix
{
  raw = <derivation>;        # Raw model before validation
  meta = {
    org = "meta-llama";
    model = "Llama-2-7b-hf";
    sourceType = "huggingface";
    repo = "meta-llama/Llama-2-7b-hf";
    revision = "main";
  };
  hfCachePath = "models--meta-llama--Llama-2-7b-hf";
}
```

### instantiate

Instantiate model definitions with a specific pkgs instance.

**Signature:**

```nix
instantiate :: Nixpkgs -> AttrSet -> AttrSet
```

**Arguments:**

- `pkgs` - Nixpkgs instance.
- `modelDefs` - Attribute set of model definitions.

**Returns:** Attribute set of derivations.

**Example:**

```nix
let
  modelDefs = {
    llama = {
      name = "llama-2";
      source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
      hash = "sha256-...";
    };
    bert = {
      name = "bert";
      source.huggingface.repo = "google-bert/bert-base-uncased";
      hash = "sha256-...";
    };
  };
in
  nix-model-repo.lib.instantiate pkgs modelDefs
  # Returns: { llama = <derivation>; bert = <derivation>; }
```

## Source Functions

### lib.sources

Source adapter factories and utilities.

#### mkHuggingFace

Create a HuggingFace source factory.

```nix
mkHuggingFace :: AttrSet -> String -> AttrSet
```

**Example:**

```nix
let
  hf = nix-model-repo.lib.sources.mkHuggingFace {
    defaultAuth.tokenEnvVar = "HF_TOKEN";
  };
in
  fetchModel pkgs {
    name = "llama";
    source = hf "meta-llama/Llama-2-7b-hf";
    hash = "sha256-...";
  }
```

#### mkS3

Create an S3 source factory.

```nix
mkS3 :: AttrSet -> String -> AttrSet
```

**Example:**

```nix
let
  s3 = nix-model-repo.lib.sources.mkS3 {
    bucket = "my-models";
    region = "us-west-2";
  };
in
  fetchModel pkgs {
    name = "model";
    source = s3 "models/llama/";  # prefix within bucket
    hash = "sha256-...";
  }
```

#### mkMlflow

Create an MLFlow source factory.

```nix
mkMlflow :: AttrSet -> String -> AttrSet
```

**Example:**

```nix
let
  mlflow = nix-model-repo.lib.sources.mkMlflow {
    trackingUri = "https://mlflow.company.com";
    defaultAuth.tokenEnvVar = "MLFLOW_TOKEN";
  };
in
  fetchModel pkgs {
    name = "model";
    source = mlflow { name = "classifier"; version = "3"; };
    hash = "sha256-...";
  }
```

#### mkGitLfs

Create a Git LFS source factory.

```nix
mkGitLfs :: AttrSet -> String -> AttrSet
```

**Example:**

```nix
let
  git = nix-model-repo.lib.sources.mkGitLfs {
    baseUrl = "https://github.com/company";
  };
in
  fetchModel pkgs {
    name = "model";
    source = git { repo = "ml-models"; rev = "v1.0"; subdir = "bert"; };
    hash = "sha256-...";
  }
```

## Validation Functions

### lib.validation

Validation utilities and factories.

#### mkValidator

Create a custom validator.

**Signature:**

```nix
mkValidator :: AttrSet -> Validator
```

**Arguments:**

```nix
{
  name = "validator-name";       # Required: unique identifier
  description = "...";           # Optional: human-readable description
  command = "shell script";      # Required: validation script
  timeout = 300;                 # Optional: timeout in seconds
  onFailure = "abort";           # Optional: "abort" | "warn" | "skip"
  buildInputs = [];              # Optional: additional dependencies
}
```

**Example:**

```nix
let
  mkValidator = nix-model-repo.lib.validation.mkValidator;

  checkLicense = mkValidator {
    name = "check-license";
    description = "Verify license file exists";
    command = ''
      if [ ! -f "$src/LICENSE" ]; then
        echo "No license file found"
        exit 1
      fi
    '';
  };
in
  fetchModel pkgs {
    name = "model";
    source.huggingface.repo = "org/model";
    hash = "sha256-...";
    validation.validators = [ checkLicense ];
  }
```

#### presets

Pre-configured validation settings.

```nix
nix-model-repo.lib.validation.presets = {
  strict = { ... };    # Maximum security
  standard = { ... };  # Balanced defaults
  minimal = { ... };   # Fast, warnings only
  none = { ... };      # Disabled
  paranoid = { ... };  # Extra thorough
};
```

#### validators

Built-in validators.

```nix
nix-model-repo.lib.validation.validators = {
  noPickleFiles = <validator>;
  safetensorsOnly = <validator>;
  maxSize = size: <validator>;
  requiredFiles = files: <validator>;
  noSymlinks = <validator>;
  fileTypes = extensions: <validator>;
  modelscan = <validator>;
};
```

## Integration Functions

### lib.integration

HuggingFace integration utilities.

#### mkCacheName

Generate HuggingFace cache directory name.

**Signature:**

```nix
mkCacheName :: AttrSet -> String
```

**Example:**

```nix
nix-model-repo.lib.integration.mkCacheName {
  org = "meta-llama";
  model = "Llama-2-7b-hf";
}
# Returns: "models--meta-llama--Llama-2-7b-hf"
```

#### mkLinkScript

Generate a shell script to link model to HF cache.

**Signature:**

```nix
mkLinkScript :: AttrSet -> String
```

**Example:**

```nix
nix-model-repo.lib.integration.mkLinkScript {
  model = myModel;
  cacheDir = "$HOME/.cache/huggingface/hub";
}
```

#### getModelPath

Get the snapshot path for a model.

**Signature:**

```nix
getModelPath :: Derivation -> String
```

**Example:**

```nix
nix-model-repo.lib.integration.getModelPath myModel
# Returns path to the latest snapshot
```

## Flake Outputs

The flake provides these outputs:

### lib

Library functions (system-independent).

```nix
nix-model-repo.lib = {
  fetchModel = pkgs: config: <derivation>;
  instantiate = pkgs: defs: <attrset>;
  sources = { mkHuggingFace, mkS3, mkMlflow, ... };
  validation = { mkValidator, presets, validators };
  integration = { mkCacheName, mkLinkScript, getModelPath };
};
```

### models

Pre-defined models (per-system).

```nix
nix-model-repo.models.x86_64-linux = {
  # Test models
  test.empty = <derivation>;
  test.minimal = <derivation>;
};
```

### modelDefs

Raw model definitions (for customization).

```nix
nix-model-repo.modelDefs = {
  test.empty = { name = "..."; source = ...; hash = "..."; };
};
```

### nixosModules

NixOS module for system-wide model management.

```nix
nix-model-repo.nixosModules.default
```

### homeManagerModules

Home Manager module for per-user model management.

```nix
nix-model-repo.homeManagerModules.default
```

## Type Reference

### SourceConfig

```nix
# HuggingFace
source.huggingface = {
  repo = "org/model";      # Required
  revision = "main";       # Optional
  files = [ ... ];         # Optional
};

# S3
source.s3 = {
  bucket = "name";         # Required
  prefix = "path/";        # Required
  region = "us-east-1";    # Optional
  endpoint = null;         # Optional
};

# MLFlow
source.mlflow = {
  trackingUri = "url";     # Required
  modelName = "name";      # Required
  version = "1";           # Required (or stage)
  stage = "Production";    # Alternative to version
};

# Git LFS
source.git-lfs = {
  url = "https://...";     # Required
  rev = "main";            # Required
  subdir = null;           # Optional
};

# Git-Xet
source.git-xet = {
  url = "xet://...";       # Required
  rev = "main";            # Required
};

# URL
source.url = {
  url = "https://...";     # Required
  extract = false;         # Optional
};

# Ollama
source.ollama = {
  model = "name";          # Required
  tag = "latest";          # Optional
};

# Mock (testing)
source.mock = {
  org = "test";            # Optional
  model = "model";         # Optional
  files = [ ... ];         # Optional
};
```

### ValidationConfig

```nix
validation = {
  enable = true;           # bool
  skipDefaults = false;    # bool
  validators = [ ... ];    # list of Validator
  onFailure = "abort";     # "abort" | "warn" | "skip"
  timeout = 300;           # int (seconds)
};
```

### NetworkConfig

```nix
network = {
  timeout = {
    connect = 30;          # int (seconds)
    read = 300;            # int (seconds)
  };
  retry = {
    maxAttempts = 3;       # int
    baseDelay = 2;         # int (seconds)
  };
  bandwidth.limit = null;  # string | null (e.g., "10M")
  proxy = null;            # string | null
};
```

### AuthConfig

```nix
auth = {
  tokenEnvVar = null;      # string | null
  tokenFile = null;        # path | null
};
```

### IntegrationConfig

```nix
integration = {
  huggingface = {
    enable = true;         # bool
    org = null;            # string | null
    model = null;          # string | null
  };
};
```
