# NixOS & Home Manager Modules

Nix Model Repo provides modules for system-wide and per-user model management.

## NixOS Module

The NixOS module enables system-wide AI model management with automatic
HuggingFace cache integration.

### Installation

Add to your flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { nixpkgs, nix-model-repo, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-model-repo.nixosModules.default
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
  services.model-repo = {
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
services.model-repo = {
  # Enable the service
  enable = true;

  # Model definitions
  models = {
    <name> = {
      name = "<name>";              # Optional, defaults to attr name
      source = { ... };             # Source configuration (required)
      hash = "sha256-...";          # Model hash (required)
      validation = { ... };         # Optional validation settings
      integration = { ... };        # Optional integration settings
      network = { ... };            # Optional network settings
      auth = { ... };               # Optional authentication
      meta = { ... };               # Optional metadata
    };
  };

  # HuggingFace integration
  integration.huggingface = {
    enable = true;                  # Create HF cache structure (default: true)
    cacheDir = "/var/cache/huggingface";  # Cache location
  };

  # User/group ownership
  user = "root";                    # User that owns the cache (default: root)
  group = "model-repo";             # Group with read access (default: model-repo)
  createGroup = true;               # Create the group (default: true)

  # Authentication (for gated models)
  auth = {
    tokenFile = "/run/secrets/hf-token";  # Path to token file
  };

  # Default settings for all models
  globalValidation = { ... };       # Default validation settings
  globalNetwork = { ... };          # Default network settings

  # Read-only: access model paths
  # modelPaths.<name> gives the store path
};
```

### Service Integration

The module creates a systemd service that:

1. Creates the HuggingFace cache directory structure
2. Symlinks all configured models
3. Sets up proper permissions for the configured group

```nix
{
  services.model-repo = {
    enable = true;
    models.llama = { ... };
  };

  # Use in other services
  systemd.services.my-inference = {
    after = [ "model-repo.service" ];
    requires = [ "model-repo.service" ];

    environment = {
      HF_HOME = "/var/cache/huggingface";
      HF_HUB_OFFLINE = "1";
      MODEL_PATH = "${config.services.model-repo.modelPaths.llama}";
    };

    serviceConfig = {
      User = "inference";
      Group = "model-repo";  # Add to model-repo group for access
    };
  };

  # Add user to model-repo group
  users.users.inference.extraGroups = [ "model-repo" ];
}
```

### Container Integration

Make models available in NixOS containers:

```nix
{
  services.model-repo = {
    enable = true;
    models.llama = { ... };
  };

  containers.inference = {
    bindMounts = {
      "/models" = {
        hostPath = "${config.services.model-repo.modelPaths.llama}";
        isReadOnly = true;
      };
    };

    config = { ... }: {
      environment.variables.MODEL_PATH = "/models";
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
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { nixpkgs, home-manager, nix-model-repo, ... }: {
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        nix-model-repo.homeManagerModules.default
        ./home.nix
      ];
    };
  };
}
```

### For nix-darwin Users

When using nix-darwin with home-manager, add the module to `home-manager.sharedModules`:

```nix
# flake.nix or darwin configuration
{
  home-manager.sharedModules = [
    nix-model-repo.homeManagerModules.default
  ];
}
```

### Basic Configuration

```nix
# home.nix
{ config, pkgs, ... }:

{
  programs.model-repo = {
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
programs.model-repo = {
  # Enable model management
  enable = true;

  # Model definitions
  models = {
    <name> = {
      name = "<name>";              # Optional, defaults to attr name
      source = { ... };             # Source configuration (required)
      hash = "sha256-...";          # Model hash (required)
      validation = { ... };         # Optional validation settings
      integration = { ... };        # Optional integration settings
      network = { ... };            # Optional network settings
      auth = { ... };               # Optional authentication
      meta = { ... };               # Optional metadata
    };
  };

  # HuggingFace integration
  integration.huggingface = {
    enable = false;                 # Enable HF cache integration
    cacheDir = null;                # Custom cache dir (default: $XDG_CACHE_HOME/huggingface)
    offlineMode = true;             # Set HF_HUB_OFFLINE=1 (default: true)
    setupOnActivation = true;       # Setup symlinks on activation (default: true)
  };

  # Default settings for all models
  globalValidation = { ... };       # Default validation settings
  globalNetwork = { ... };          # Default network settings

  # Read-only: access model paths
  # modelPaths.<name> gives the store path
};
```

### Activation Script

Home Manager creates an activation script that:

1. Creates the HuggingFace cache directory
2. Symlinks all HuggingFace models to the cache
3. Sets up environment variables (HF_HUB_OFFLINE, TRANSFORMERS_OFFLINE)

### Using Model Paths

Access model paths in other parts of your configuration:

```nix
{ config, pkgs, ... }:

{
  programs.model-repo = {
    enable = true;
    models.bert = {
      source.huggingface.repo = "google-bert/bert-base-uncased";
      hash = "sha256-...";
    };
    integration.huggingface.enable = true;
  };

  # Use the model path elsewhere
  home.sessionVariables = {
    BERT_MODEL_PATH = "${config.programs.model-repo.modelPaths.bert}";
  };
}
```

### Development Environment

Combine with development shells:

```nix
{ config, pkgs, ... }:

{
  programs.model-repo = {
    enable = true;
    models.bert = {
      source.huggingface.repo = "google-bert/bert-base-uncased";
      hash = "sha256-...";
    };
    integration.huggingface.enable = true;
  };

  # Python development with models
  home.packages = [
    (pkgs.python3.withPackages (ps: [
      ps.transformers
      ps.torch
    ]))
  ];
}
```

## Example Configurations

### Production Server (NixOS)

```nix
# NixOS configuration for an inference server
{ config, pkgs, lib, ... }:

{
  services.model-repo = {
    enable = true;
    group = "inference";

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
      };
    };

    integration.huggingface.cacheDir = "/data/models";
    auth.tokenFile = config.sops.secrets.hf-token.path;
  };

  # Inference service
  systemd.services.vllm = {
    after = [ "model-repo.service" ];
    requires = [ "model-repo.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HF_HOME = "/data/models";
      HF_HUB_OFFLINE = "1";
    };

    serviceConfig = {
      ExecStart = "${pkgs.vllm}/bin/vllm serve meta-llama/Llama-2-70b-chat-hf";
      User = "vllm";
      Group = "inference";
    };
  };

  users.users.vllm = {
    isSystemUser = true;
    group = "inference";
  };
  users.groups.inference = {};
}
```

### Development Workstation (Home Manager)

```nix
# Home Manager for ML developer
{ config, pkgs, ... }:

{
  programs.model-repo = {
    enable = true;

    models = {
      # Small models for development
      bert-tiny = {
        source.huggingface.repo = "prajjwal1/bert-tiny";
        hash = "sha256-...";
      };

      # Production model for testing
      mistral-7b = {
        source.huggingface.repo = "mistralai/Mistral-7B-v0.1";
        hash = "sha256-...";
      };
    };

    integration.huggingface = {
      enable = true;
      offlineMode = true;
    };
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

### Multi-Model Pipeline (NixOS)

```nix
# Configuration for a multi-model pipeline
{ config, lib, pkgs, ... }:

{
  services.model-repo = {
    enable = true;

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
  };

  # Each stage of the pipeline
  systemd.services = {
    embedding-service = {
      after = [ "model-repo.service" ];
      environment.MODEL_PATH = "${config.services.model-repo.modelPaths.embedding}";
      # ...
    };
    reranker-service = {
      after = [ "model-repo.service" ];
      environment.MODEL_PATH = "${config.services.model-repo.modelPaths.reranker}";
      # ...
    };
    generator-service = {
      after = [ "model-repo.service" ];
      environment.MODEL_PATH = "${config.services.model-repo.modelPaths.generator}";
      # ...
    };
  };
}
```

## Troubleshooting

### Module Not Found

Ensure the module is added to your configuration:

```nix
# For NixOS
modules = [
  nix-model-repo.nixosModules.default
  ./your-config.nix
];

# For Home Manager (standalone)
modules = [
  nix-model-repo.homeManagerModules.default
  ./home.nix
];

# For Home Manager (with nix-darwin)
home-manager.sharedModules = [
  nix-model-repo.homeManagerModules.default
];
```

### Option Does Not Exist

If you see errors like `The option 'programs.model-repo.models' does not exist`:

1. Make sure the module is imported correctly (see above)
2. For nix-darwin, ensure the module is in `home-manager.sharedModules`, not the darwin modules list
3. Run `nix flake update` to get the latest version

### Models Not Linking

Check the activation log:

```bash
# NixOS
journalctl -u model-repo

# Home Manager
cat ~/.local/state/home-manager/activation.log
```

Verify the cache directory exists and has correct permissions:

```bash
ls -la ~/.cache/huggingface/hub/  # Home Manager
ls -la /var/cache/huggingface/hub/  # NixOS
```

### Permission Denied

For NixOS, ensure your user is in the `model-repo` group:

```nix
users.users.myuser.extraGroups = [ "model-repo" ];
```

### Hash Mismatch

When a model updates upstream, you'll get a hash mismatch error. Update the hash in your configuration:

```bash
# The error message will show the correct hash
# got: sha256-NEW_HASH_HERE...
```
