# NixOS & Home Manager Modules

Nix AI Models provides modules for system-wide and per-user model management.

## NixOS Module

The NixOS module enables system-wide AI model management with automatic
HuggingFace cache integration.

### Installation

Add to your flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { nixpkgs, nix-ai-models, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-ai-models.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### Basic Configuration

```nix
# configuration.nix
{ config, pkgs, ... }:

{
  services.ai-models = {
    enable = true;

    models = {
      llama-2-7b = {
        source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
        hash = "sha256-...";
      };

      bert-base = {
        source.huggingface.repo = "google-bert/bert-base-uncased";
        hash = "sha256-...";
      };
    };
  };
}
```

### Full Options Reference

```nix
services.ai-models = {
  # Enable the service
  enable = true;

  # Model definitions
  models = {
    <name> = {
      source = { ... };           # Source configuration
      hash = "sha256-...";        # Model hash
      validation = { ... };       # Optional validation settings
    };
  };

  # HuggingFace integration
  integration.huggingface = {
    enable = true;                # Create HF cache structure
    cacheDir = "/var/cache/huggingface/hub";  # Cache location
  };

  # Default validation settings
  validation = {
    preset = "standard";          # Default preset for all models
  };

  # Authentication (for gated models)
  auth = {
    tokenFile = "/run/secrets/hf-token";  # Path to token file
  };

  # Users/groups with access
  group = "ai-models";            # Group with read access
};
```

### Service Integration

The module creates a systemd service that:

1. Builds all configured models
2. Creates HuggingFace cache symlinks
3. Sets up proper permissions

```nix
{
  services.ai-models = {
    enable = true;
    models.llama = { ... };
  };

  # Use in other services
  systemd.services.my-inference = {
    after = [ "ai-models.service" ];
    environment = {
      HF_HOME = "/var/cache/huggingface";
      HF_HUB_OFFLINE = "1";
    };
  };
}
```

### Container Integration

Make models available in NixOS containers:

```nix
{
  services.ai-models = {
    enable = true;
    models.llama = { ... };
  };

  containers.inference = {
    bindMounts = {
      "/models" = {
        hostPath = config.services.ai-models.modelPaths.llama;
        isReadOnly = true;
      };
    };

    config = { ... }: {
      environment.variables.HF_HOME = "/models";
    };
  };
}
```

## Home Manager Module

The Home Manager module provides per-user model management.

### Installation

Add to your home-manager configuration:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { nixpkgs, home-manager, nix-ai-models, ... }: {
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        nix-ai-models.homeManagerModules.default
        ./home.nix
      ];
    };
  };
}
```

### Basic Configuration

```nix
# home.nix
{ config, pkgs, ... }:

{
  programs.ai-models = {
    enable = true;

    models = {
      mistral = {
        source.huggingface.repo = "mistralai/Mistral-7B-v0.1";
        hash = "sha256-...";
      };
    };

    # Automatically link to ~/.cache/huggingface/hub
    integration.huggingface.enable = true;
  };
}
```

### Full Options Reference

```nix
programs.ai-models = {
  # Enable model management
  enable = true;

  # Model definitions
  models = {
    <name> = {
      source = { ... };
      hash = "sha256-...";
      validation = { ... };
    };
  };

  # HuggingFace integration
  integration.huggingface = {
    enable = true;
    cacheDir = "${config.xdg.cacheHome}/huggingface/hub";
  };

  # Default validation
  validation.preset = "standard";

  # Authentication
  auth = {
    tokenEnvVar = "HF_TOKEN";       # Environment variable
    # OR
    tokenFile = "~/.config/huggingface/token";  # File path
  };

  # Session variables
  sessionVariables = {
    HF_HUB_OFFLINE = "1";           # Additional env vars
  };
};
```

### Activation Script

Home Manager creates an activation script that:

1. Symlinks models to the HuggingFace cache
2. Sets up environment variables
3. Cleans up stale links

### Development Environment

Combine with development shells:

```nix
{ config, pkgs, ... }:

{
  programs.ai-models = {
    enable = true;
    models.bert = { ... };
  };

  # Python development with models
  home.packages = [
    (pkgs.python3.withPackages (ps: [
      ps.transformers
      ps.torch
    ]))
  ];

  # Environment setup
  home.sessionVariables = {
    HF_HUB_OFFLINE = "1";
    TRANSFORMERS_OFFLINE = "1";
  };
}
```

## Example Configurations

### Production Server

```nix
# NixOS configuration for an inference server
{ config, pkgs, ... }:

{
  services.ai-models = {
    enable = true;

    models = {
      llama-2-70b = {
        source.huggingface = {
          repo = "meta-llama/Llama-2-70b-chat-hf";
          files = [
            "config.json"
            "tokenizer.json"
            "tokenizer_config.json"
            "model.safetensors.index.json"
          ] ++ (map (i: "model-${toString i}-of-00015.safetensors")
                    (lib.range 1 15));
        };
        hash = "sha256-...";
        validation = nix-ai-models.lib.validation.presets.strict;
      };
    };

    integration.huggingface.cacheDir = "/data/models";
    auth.tokenFile = config.sops.secrets.hf-token.path;
  };

  # Inference service
  systemd.services.vllm = {
    after = [ "ai-models.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HF_HOME = "/data/models";
      HF_HUB_OFFLINE = "1";
    };

    serviceConfig = {
      ExecStart = "${pkgs.vllm}/bin/vllm serve meta-llama/Llama-2-70b-chat-hf";
      User = "vllm";
      Group = "ai-models";
    };
  };
}
```

### Development Workstation

```nix
# Home Manager for ML developer
{ config, pkgs, ... }:

{
  programs.ai-models = {
    enable = true;

    models = {
      # Small models for development
      bert-tiny = {
        source.huggingface.repo = "prajjwal1/bert-tiny";
        hash = "sha256-...";
        validation.preset = "minimal";
      };

      # Production model for testing
      mistral-7b = {
        source.huggingface.repo = "mistralai/Mistral-7B-v0.1";
        hash = "sha256-...";
      };
    };

    integration.huggingface.enable = true;
    auth.tokenEnvVar = "HF_TOKEN";
  };

  # Development tools
  home.packages = with pkgs; [
    python311
    python311Packages.transformers
    python311Packages.accelerate
    python311Packages.torch
  ];

  # Aliases for common operations
  programs.zsh.shellAliases = {
    hf-offline = "export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1";
    hf-online = "unset HF_HUB_OFFLINE TRANSFORMERS_OFFLINE";
  };
}
```

### Multi-Model Pipeline

```nix
# Configuration for a multi-model pipeline
{ config, lib, pkgs, ... }:

let
  models = {
    embedding = {
      source.huggingface.repo = "sentence-transformers/all-MiniLM-L6-v2";
      hash = "sha256-...";
    };
    reranker = {
      source.huggingface.repo = "cross-encoder/ms-marco-MiniLM-L-6-v2";
      hash = "sha256-...";
    };
    generator = {
      source.huggingface.repo = "mistralai/Mistral-7B-Instruct-v0.1";
      hash = "sha256-...";
    };
  };
in {
  services.ai-models = {
    enable = true;
    inherit models;
  };

  # Each stage of the pipeline
  systemd.services = {
    embedding-service = {
      environment.MODEL_PATH = config.services.ai-models.modelPaths.embedding;
      # ...
    };
    reranker-service = {
      environment.MODEL_PATH = config.services.ai-models.modelPaths.reranker;
      # ...
    };
    generator-service = {
      environment.MODEL_PATH = config.services.ai-models.modelPaths.generator;
      # ...
    };
  };
}
```

## Troubleshooting

### Module Not Found

Ensure the module is added to your configuration:

```nix
modules = [
  nix-ai-models.nixosModules.default  # or homeManagerModules.default
  ./your-config.nix
];
```

### Models Not Linking

Check the activation log:

```bash
# NixOS
journalctl -u ai-models

# Home Manager
cat ~/.local/state/home-manager/activation.log
```

### Permission Denied

Ensure your user is in the `ai-models` group:

```nix
users.users.myuser.extraGroups = [ "ai-models" ];
```
