# HuggingFace Integration

Nix AI Models creates a HuggingFace-compatible cache structure that allows
seamless integration with the `transformers` library and other HuggingFace tools.

## How It Works

The HuggingFace `transformers` library expects models in a specific cache structure:

```
~/.cache/huggingface/hub/
└── models--{org}--{model}/
    ├── blobs/
    │   └── {sha256-hash}           # Actual file content
    ├── refs/
    │   └── main                    # Points to commit SHA
    └── snapshots/
        └── {commit-sha}/
            ├── config.json -> ../../blobs/{hash}
            ├── model.safetensors -> ../../blobs/{hash}
            └── ...
```

Nix AI Models creates this exact structure, allowing you to symlink the Nix store
path to your HuggingFace cache directory.

## Basic Integration

After fetching a model, link it to your HuggingFace cache:

```bash
# Build the model
nix build .#llama-2-7b

# Link to HuggingFace cache
mkdir -p ~/.cache/huggingface/hub
ln -s $(readlink -f result) ~/.cache/huggingface/hub/models--meta-llama--Llama-2-7b-hf
```

Now you can use it directly with transformers:

```python
from transformers import AutoModelForCausalLM

# Transformers will find it in the cache!
model = AutoModelForCausalLM.from_pretrained("meta-llama/Llama-2-7b-hf")
```

## Automatic Integration Options

Configure automatic cache structure creation:

```nix
fetchModel pkgs {
  name = "llama-2-7b";
  source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
  hash = "sha256-...";

  integration.huggingface = {
    enable = true;      # Default: true
    org = null;         # Override org name (default: from source)
    model = null;       # Override model name (default: from source)
  };
}
```

### Override Names

For models from non-HuggingFace sources, set the integration names:

```nix
fetchModel pkgs {
  name = "my-finetuned-llama";
  source.s3 = {
    bucket = "my-models";
    prefix = "fine-tuned/llama/";
  };
  hash = "sha256-...";

  integration.huggingface = {
    enable = true;
    org = "my-org";
    model = "fine-tuned-llama";
  };
}
```

This creates the cache structure for `my-org/fine-tuned-llama`.

## NixOS Module Integration

The NixOS module provides system-wide model management:

```nix
# configuration.nix
{
  services.ai-models = {
    enable = true;

    models = {
      llama-2-7b = {
        source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
        hash = "sha256-...";
      };
      mistral-7b = {
        source.huggingface.repo = "mistralai/Mistral-7B-v0.1";
        hash = "sha256-...";
      };
    };

    # Create cache links for all users
    integration.huggingface.enable = true;
  };
}
```

This automatically:

1. Fetches all models to the Nix store
2. Creates symlinks in `/var/cache/huggingface/hub/`
3. Sets `HF_HOME` environment variable for system services

## Home Manager Integration

For per-user model management:

```nix
# home.nix
{
  programs.ai-models = {
    enable = true;

    models = {
      bert = {
        source.huggingface.repo = "google-bert/bert-base-uncased";
        hash = "sha256-...";
      };
    };

    integration.huggingface = {
      enable = true;
      # Automatically links to ~/.cache/huggingface/hub/
    };
  };
}
```

## Using with Python/venv

In a development shell with the model:

```nix
# flake.nix
{
  devShells.default = pkgs.mkShell {
    packages = [ pkgs.python3 ];

    shellHook = ''
      # Link model to HF cache
      mkdir -p ~/.cache/huggingface/hub
      ln -sfn ${self.packages.${system}.llama-2-7b} \
        ~/.cache/huggingface/hub/models--meta-llama--Llama-2-7b-hf

      export HF_HUB_OFFLINE=1  # Prevent downloads
    '';
  };
}
```

## Using with Containers

Mount the Nix store path as a volume:

### Docker

```dockerfile
# The model path comes from Nix
FROM python:3.11

# Mount point for the model
VOLUME /models

# Point transformers to our models
ENV HF_HOME=/models
```

```bash
# Build and get the store path
MODEL_PATH=$(nix build .#llama-2-7b --print-out-paths)

# Run with the model mounted
docker run -v $MODEL_PATH:/models/hub/models--meta-llama--Llama-2-7b-hf myapp
```

### NixOS Containers

```nix
containers.inference = {
  config = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.python3 ];
  };

  bindMounts = {
    "/var/cache/huggingface/hub/models--meta-llama--Llama-2-7b-hf" = {
      hostPath = "${self.packages.x86_64-linux.llama-2-7b}";
      isReadOnly = true;
    };
  };
};
```

## Offline Usage

Once models are in the Nix store, you can use them completely offline:

```python
import os
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

from transformers import AutoModel
model = AutoModel.from_pretrained("meta-llama/Llama-2-7b-hf")
```

Or set environment variables in your shell:

```nix
devShells.default = pkgs.mkShell {
  HF_HUB_OFFLINE = "1";
  TRANSFORMERS_OFFLINE = "1";
};
```

## Model Metadata

Each fetched model includes metadata accessible via passthru:

```nix
let
  model = fetchModel pkgs {
    name = "llama-2-7b";
    source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
    hash = "sha256-...";
  };
in {
  # Access metadata
  org = model.passthru.meta.org;           # "meta-llama"
  modelName = model.passthru.meta.model;   # "Llama-2-7b-hf"
  source = model.passthru.meta.sourceType; # "huggingface"

  # HF cache path component
  cachePath = model.passthru.hfCachePath;  # "models--meta-llama--Llama-2-7b-hf"
}
```

## Integration Helper Functions

The library provides helper functions for common integration tasks:

```nix
let
  integration = nix-ai-models.lib.integration;
in {
  # Generate cache directory name
  cacheName = integration.mkCacheName {
    org = "meta-llama";
    model = "Llama-2-7b-hf";
  };
  # Returns: "models--meta-llama--Llama-2-7b-hf"

  # Create symlink script
  linkScript = integration.mkLinkScript {
    model = myModel;
    cacheDir = "$HOME/.cache/huggingface/hub";
  };

  # Get model path for transformers
  modelPath = integration.getModelPath myModel;
}
```

## Troubleshooting

### Model Not Found

If transformers can't find the model:

1. Check the symlink exists and points to the correct store path
2. Verify the cache directory structure matches HuggingFace's expected format
3. Check that `HF_HOME` or `HF_HUB_CACHE` is set correctly

```bash
# Debug: check cache structure
ls -la ~/.cache/huggingface/hub/
ls -la ~/.cache/huggingface/hub/models--meta-llama--Llama-2-7b-hf/
```

### Permission Errors

The Nix store is read-only. If an application tries to write to the model:

```python
# Set model to eval mode to prevent gradient writes
model.eval()

# Or use a writable cache for any needed writes
os.environ["HF_HOME"] = "/tmp/hf-cache"
```

### Hash Mismatch on Update

If the model updated and the hash no longer matches:

1. Get the new hash from the error message
2. Update your configuration
3. Rebuild

```bash
# Nix will show the expected hash on failure
nix build .#my-model
# error: hash mismatch in fixed-output derivation
#   specified: sha256-old...
#   got:       sha256-new...
```
