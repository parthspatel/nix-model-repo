# Devenv Integration

Nix Model Repo provides a [devenv](https://devenv.sh) module for seamless integration
with devenv-based development environments.

## Installation

### Using devenv.yaml (Recommended)

Add nix-model-repo as an input in your `devenv.yaml`:

```yaml
inputs:
  nix-model-repo:
    url: github:parthspatel/nix-model-repo
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
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
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

### Full Options Reference

#### `services.model-repo.enable`

- **Type:** `bool`
- **Default:** `false`

Enable AI model management.

#### `services.model-repo.models`

- **Type:** `attrsOf model`
- **Default:** `{}`

Attribute set of models to fetch. Each model has:

| Option        | Type     | Required | Description                                  |
| ------------- | -------- | -------- | -------------------------------------------- |
| `name`        | `string` | No       | Model name (defaults to attribute name)      |
| `source`      | `attrs`  | Yes      | Source configuration (huggingface, s3, etc.) |
| `hash`        | `string` | Yes      | SHA256 hash in SRI format                    |
| `validation`  | `attrs`  | No       | Validation settings                          |
| `integration` | `attrs`  | No       | Integration settings                         |
| `network`     | `attrs`  | No       | Network settings (timeouts, retries)         |
| `auth`        | `attrs`  | No       | Authentication configuration                 |
| `meta`        | `attrs`  | No       | Metadata                                     |

#### `services.model-repo.cacheDir`

- **Type:** `string`
- **Default:** `".devenv/model-repo"`

Directory for HuggingFace cache symlinks (relative to project root).

#### `services.model-repo.linkToHuggingFace`

- **Type:** `bool`
- **Default:** `true`

Create symlinks in HuggingFace cache directory structure.

#### `services.model-repo.offlineMode`

- **Type:** `bool`
- **Default:** `true`

Set `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` after models are linked.

#### `services.model-repo.globalValidation`

- **Type:** `attrs`
- **Default:** `{}`

Default validation settings applied to all models.

#### `services.model-repo.globalNetwork`

- **Type:** `attrs`
- **Default:** `{}`

Default network settings applied to all models.

## Environment Variables

When enabled, the module sets:

| Variable               | Value      | Description                                                    |
| ---------------------- | ---------- | -------------------------------------------------------------- |
| `MODEL_REPO_<NAME>`    | Store path | Path to each model (uppercase name, dashes become underscores) |
| `HF_HOME`              | Cache dir  | HuggingFace cache directory (set in enterShell)                |
| `HF_HUB_OFFLINE`       | `1`        | Prevent downloads (if offlineMode enabled)                     |
| `TRANSFORMERS_OFFLINE` | `1`        | Prevent downloads (if offlineMode enabled)                     |

Example: A model named `bert-base` will have environment variable `MODEL_REPO_BERT_BASE`.

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

      # Non-HuggingFace source example
      custom-model = {
        source.s3 = {
          bucket = "my-models";
          prefix = "custom/";
          region = "us-east-1";
        };
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
    pkgs.python311Packages.transformers
    pkgs.python311Packages.torch
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
    echo "Models: bert, gpt2, custom-model"
    echo ""
    echo "Try: test-model"
  '';
}
```

## Using Model Paths

Access model paths via environment variables in your scripts:

```nix
# devenv.nix
{ pkgs, lib, inputs, ... }:

{
  imports = [ inputs.nix-model-repo.devenvModules.default ];

  services.model-repo = {
    enable = true;
    models.bert = {
      source.huggingface.repo = "google-bert/bert-base-uncased";
      hash = "sha256-...";
    };
  };

  scripts.use-model.exec = ''
    echo "BERT model path: $MODEL_REPO_BERT"
    python my_script.py --model-path "$MODEL_REPO_BERT"
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

## Source Types

The module supports all source types from nix-model-repo:

### HuggingFace

```nix
models.llama = {
  source.huggingface = {
    repo = "meta-llama/Llama-2-7b-hf";
    revision = "main";  # Optional, defaults to main
    files = [ "config.json" "*.safetensors" ];  # Optional, download specific files
  };
  hash = "sha256-...";
};
```

### S3

```nix
models.custom = {
  source.s3 = {
    bucket = "my-bucket";
    prefix = "models/my-model/";
    region = "us-east-1";
  };
  hash = "sha256-...";
  auth.awsProfile = "my-profile";  # Optional
};
```

### Git LFS

```nix
models.my-model = {
  source.git-lfs = {
    url = "https://github.com/org/model-repo.git";
    rev = "abc123...";
  };
  hash = "sha256-...";
};
```

### Direct URL

```nix
models.weights = {
  source.url = {
    urls = [ "https://example.com/model.bin" ];
  };
  hash = "sha256-...";
};
```

## Troubleshooting

### Model Not Found After Shell Entry

Ensure the symlinks are created correctly:

```bash
ls -la .devenv/model-repo/
```

Check that HF_HOME is set:

```bash
echo $HF_HOME
```

### Hash Mismatch

Update the hash in your configuration. The build will fail with the correct hash:

```bash
devenv shell
# error: hash mismatch in fixed-output derivation
#   specified: sha256-old...
#   got:       sha256-NEW_HASH_HERE...
```

Copy the `got:` hash to your configuration.

### Authentication for Gated Models

Set your HuggingFace token before entering the shell:

```bash
export HF_TOKEN="hf_..."
devenv shell
```

Or use a `.envrc` file with direnv:

```bash
# .envrc
export HF_TOKEN="hf_..."
```

### Offline Mode Issues

If you need to download new models, temporarily disable offline mode:

```nix
services.model-repo.offlineMode = false;
```

Or manually in your shell:

```bash
unset HF_HUB_OFFLINE TRANSFORMERS_OFFLINE
```

### Slow First Build

The first build downloads and validates models, which can take time for large models.
Subsequent builds use the Nix store cache and are instant.

Consider using a binary cache for your team:

```nix
# devenv.nix
{
  cachix.enable = true;
  cachix.pull = [ "my-team-cache" ];
  cachix.push = "my-team-cache";
}
```
