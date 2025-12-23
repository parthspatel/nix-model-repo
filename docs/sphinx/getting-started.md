# Getting Started

This guide will help you get started with Nix AI Models.

## Prerequisites

- Nix with flakes enabled
- Git (for fetching the flake)

### Enable Flakes

If you haven't enabled flakes yet, add this to your Nix configuration:

```nix
# /etc/nix/nix.conf or ~/.config/nix/nix.conf
experimental-features = nix-command flakes
```

## Quick Start

### 1. Add to Your Flake

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { self, nixpkgs, nix-ai-models, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-ai-models.lib.fetchModel pkgs;
  in {
    packages.${system} = {
      # Your first model
      bert = fetchModel {
        name = "bert-base-uncased";
        source.huggingface.repo = "google-bert/bert-base-uncased";
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
    };
  };
}
```

### 2. Get the Hash

The first time you build, use a placeholder hash. Nix will tell you the correct one:

```bash
$ nix build .#bert
error: hash mismatch in fixed-output derivation '/nix/store/...-bert-base-uncased':
  specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
  got:       sha256-abc123...
```

### 3. Update the Hash

Replace the placeholder with the correct hash:

```nix
hash = "sha256-abc123...";  # Use the hash from the error message
```

### 4. Build the Model

```bash
$ nix build .#bert
$ ls -la result/
```

## Using with Transformers

After building, link the model to your HuggingFace cache:

```bash
# Create cache directory
mkdir -p ~/.cache/huggingface/hub

# Link the model
ln -s $(readlink -f result) ~/.cache/huggingface/hub/models--google-bert--bert-base-uncased
```

Now use it in Python:

```python
from transformers import AutoModel

# Works offline - model is in cache!
model = AutoModel.from_pretrained("google-bert/bert-base-uncased")
```

## Next Steps

- [Configuration Reference](configuration.md) - All configuration options
- [Sources](sources.md) - Different model sources (HuggingFace, S3, MLFlow, etc.)
- [Validation](validation.md) - Security scanning and validation
- [Examples](examples.md) - Complete example configurations
- [Devenv Integration](devenv.md) - Use with devenv.sh development environments

## Common Patterns

### Development Shell with Models

```nix
{
  devShells.${system}.default = pkgs.mkShell {
    packages = [
      (pkgs.python3.withPackages (ps: [ ps.transformers ps.torch ]))
    ];

    shellHook = ''
      mkdir -p ~/.cache/huggingface/hub
      ln -sfn ${self.packages.${system}.bert} \
        ~/.cache/huggingface/hub/models--google-bert--bert-base-uncased
      export HF_HUB_OFFLINE=1
    '';
  };
}
```

### Multiple Models

```nix
let
  fetchModel = nix-ai-models.lib.fetchModel pkgs;
in {
  packages.${system} = {
    llama = fetchModel {
      name = "llama-2-7b";
      source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
      hash = "sha256-...";
      auth.tokenEnvVar = "HF_TOKEN";
    };

    mistral = fetchModel {
      name = "mistral-7b";
      source.huggingface.repo = "mistralai/Mistral-7B-v0.1";
      hash = "sha256-...";
    };

    bert = fetchModel {
      name = "bert-base";
      source.huggingface.repo = "google-bert/bert-base-uncased";
      hash = "sha256-...";
    };
  };
}
```

### Gated Models (Llama, Mistral, etc.)

For models that require authentication:

1. Get a HuggingFace token from https://huggingface.co/settings/tokens
2. Accept the model's license on HuggingFace
3. Set the token in your environment:

```bash
export HF_TOKEN="hf_..."
```

4. Configure authentication in your model:

```nix
fetchModel {
  name = "llama-2-7b";
  source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
  hash = "sha256-...";
  auth.tokenEnvVar = "HF_TOKEN";
}
```

## Using with Devenv

For [devenv.sh](https://devenv.sh) development environments, we provide a dedicated module:

```nix
# devenv.nix
{ pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.nix-ai-models.devenvModules.default
  ];

  services.ai-models = {
    enable = true;
    models.bert = {
      source.huggingface.repo = "google-bert/bert-base-uncased";
      hash = "sha256-...";
    };
  };
}
```

See the [Devenv Integration Guide](devenv.md) for full documentation and [Devenv Examples](examples.md#devenv-configuration) for complete configurations.

## Troubleshooting

### Hash Mismatch

This is expected on first build or when models update. Use the hash from the error message.

### Authentication Failed

For gated models:
1. Ensure `HF_TOKEN` is set
2. Verify you've accepted the model's license on HuggingFace
3. Check the token has read permissions

### Build Timeout

Large models may timeout. Increase the timeout:

```nix
fetchModel {
  name = "large-model";
  source.huggingface.repo = "org/model";
  hash = "sha256-...";
  network.timeout.read = 3600;  # 1 hour
}
```

## More Examples

For complete, copy-paste ready examples, see:

- [Basic Model Flake](examples.md#basic-model-flake) - Minimal setup
- [Development Environment](examples.md#development-environment-flake) - Dev shell with models
- [Production Inference](examples.md#production-inference-flake) - Production deployment
- [Devenv Configuration](examples.md#devenv-configuration) - Using with devenv.sh
