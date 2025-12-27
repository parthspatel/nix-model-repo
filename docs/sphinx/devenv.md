# Devenv Integration

Nix Model Repo provides a [devenv](https://devenv.sh) module for seamless integration
with devenv-based development environments.

## Installation

### Using devenv.yaml (Recommended)

Add nix-model-repo as an input in your `devenv.yaml`:

```yaml
inputs:
  nix-model-repo:
    url: github:your-org/nix-model-repo
```

Then import the module in your `devenv.nix`:

```nix
{ pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.nix-model-repo.devenvModules.default
  ];

  services.model-repo = {
    enable = true;
    models = {
      bert = {
        source.huggingface.repo = "google-bert/bert-base-uncased";
        hash = "sha256-...";
      };
    };
  };
}
```

### Using Flakes

If you're using devenv with flakes:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    nix-model-repo.url = "github:your-org/nix-model-repo";
  };

  outputs = { self, nixpkgs, devenv, nix-model-repo, ... }@inputs:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {
    devShells.x86_64-linux.default = devenv.lib.mkShell {
      inherit inputs pkgs;
      modules = [
        nix-model-repo.devenvModules.default
        {
          services.model-repo = {
            enable = true;
            models.bert = {
              source.huggingface.repo = "google-bert/bert-base-uncased";
              hash = "sha256-...";
            };
          };
        }
      ];
    };
  };
}
```

## Configuration

### Basic Example

```nix
{ pkgs, lib, ... }:

{
  services.model-repo = {
    enable = true;

    models = {
      # Small embedding model
      embeddings = {
        source.huggingface.repo = "sentence-transformers/all-MiniLM-L6-v2";
        hash = "sha256-...";
      };

      # Large language model (requires auth)
      llama = {
        source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
        hash = "sha256-...";
        auth.tokenEnvVar = "HF_TOKEN";
      };
    };
  };
}
```

### Options Reference

#### `services.model-repo.enable`

- **Type:** `bool`
- **Default:** `false`

Enable AI model management.

#### `services.model-repo.models`

- **Type:** `attrsOf model`
- **Default:** `{}`

Attribute set of models to fetch. Each model has:

| Option | Type | Description |
|--------|------|-------------|
| `source` | `attrs` | Source configuration (huggingface, s3, etc.) |
| `hash` | `string` | SHA256 hash in SRI format |
| `validation` | `attrs` | Optional validation settings |
| `auth` | `attrs` | Optional authentication |

#### `services.model-repo.cacheDir`

- **Type:** `string`
- **Default:** `".devenv/model-repo"`

Directory for HuggingFace cache symlinks.

#### `services.model-repo.linkToHuggingFace`

- **Type:** `bool`
- **Default:** `true`

Create symlinks in HuggingFace cache directory structure.

#### `services.model-repo.offlineMode`

- **Type:** `bool`
- **Default:** `true`

Set `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` after models are linked.

## Environment Variables

When enabled, the module sets:

| Variable | Value | Description |
|----------|-------|-------------|
| `MODEL_REPO_<NAME>` | Store path | Path to each model (uppercase name) |
| `HF_HOME` | Cache dir | HuggingFace cache directory |
| `HF_HUB_OFFLINE` | `1` | Prevent downloads (if offlineMode) |
| `TRANSFORMERS_OFFLINE` | `1` | Prevent downloads (if offlineMode) |

## Full Example

```nix
# devenv.nix
{ pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.nix-model-repo.devenvModules.default
  ];

  # Python with ML libraries
  languages.python = {
    enable = true;
    package = pkgs.python311;
    venv.enable = true;
  };

  # AI Models
  services.model-repo = {
    enable = true;

    models = {
      bert = {
        source.huggingface.repo = "google-bert/bert-base-uncased";
        hash = "sha256-...";
      };

      gpt2 = {
        source.huggingface.repo = "openai-community/gpt2";
        hash = "sha256-...";
      };
    };

    # Custom cache location
    cacheDir = ".cache/models";

    # Enable offline mode
    offlineMode = true;
  };

  # Install transformers
  packages = [
    (pkgs.python311Packages.transformers)
    (pkgs.python311Packages.torch)
  ];

  # Custom script
  scripts.test-model.exec = ''
    python -c "
    from transformers import AutoModel
    model = AutoModel.from_pretrained('google-bert/bert-base-uncased')
    print('Model loaded successfully!')
    "
  '';

  enterShell = ''
    echo "ML Development Environment"
    echo "Models: bert, gpt2"
    echo ""
    echo "Try: test-model"
  '';
}
```

## Without the Module

If you prefer not to use the module, you can use the library directly:

```nix
# devenv.nix
{ pkgs, lib, inputs, ... }:

let
  fetchModel = inputs.nix-model-repo.lib.fetchModel pkgs;

  bert = fetchModel {
    name = "bert-base";
    source.huggingface.repo = "google-bert/bert-base-uncased";
    hash = "sha256-...";
  };
in {
  packages = [ bert ];

  env.BERT_MODEL = "${bert}";

  enterShell = ''
    mkdir -p .cache/huggingface/hub
    ln -sfn ${bert} .cache/huggingface/hub/models--google-bert--bert-base-uncased
    export HF_HOME=".cache/huggingface"
    export HF_HUB_OFFLINE=1
  '';
}
```

## Troubleshooting

### Model Not Found After Shell Entry

Ensure the symlinks are created correctly:

```bash
ls -la .devenv/model-repo/
```

### Hash Mismatch

Update the hash in your configuration:

```bash
# Build will fail with correct hash
devenv shell
# Copy the "got: sha256-..." from the error
```

### Authentication for Gated Models

Set your HuggingFace token:

```bash
export HF_TOKEN="hf_..."
devenv shell
```

Or use a `.envrc` file:

```bash
export HF_TOKEN="hf_..."
```

### Offline Mode Issues

If you need to download new models, temporarily disable offline mode:

```nix
services.model-repo.offlineMode = false;
```

Or manually:

```bash
unset HF_HUB_OFFLINE TRANSFORMERS_OFFLINE
```
