# Example Flakes

This page provides complete example flake configurations for common use cases.

## Quick Links

| Example | Description | Key Features |
|---------|-------------|--------------|
| [Basic Model](#basic-model-flake) | Minimal single model setup | Simple, quick start |
| [Multi-Model](#multi-model-flake) | Multiple models in one flake | Embeddings, LLM, classifier |
| [Development Environment](#development-environment-flake) | Dev shell with models | Python, offline mode |
| [Production Inference](#production-inference-flake) | Production deployment | Strict validation, NixOS module |
| [Multi-Source](#multi-source-flake) | Different model sources | S3, MLFlow, Git LFS |
| [Validation Presets](#validation-presets-flake) | Security configurations | Presets, custom validators |
| [NixOS Configuration](#nixos-configuration-with-models) | Full NixOS integration | systemd service |
| [Home Manager](#home-manager-configuration) | User-level config | Shell integration |
| [Devenv](#devenv-configuration) | devenv.sh integration | ML development |

## Basic Model Flake

A minimal flake that fetches a single model:

```nix
# flake.nix
{
  description = "My AI Model";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { self, nixpkgs, nix-model-repo, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-model-repo.lib.fetchModel pkgs;
  in {
    packages.${system}.default = fetchModel {
      name = "bert-base";
      source.huggingface.repo = "google-bert/bert-base-uncased";
      hash = "sha256-...";
    };
  };
}
```

## Multi-Model Flake

A flake with multiple models for different purposes:

```nix
# flake.nix
{
  description = "ML Models Collection";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { self, nixpkgs, nix-model-repo, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-model-repo.lib.fetchModel pkgs;
  in {
    packages.${system} = {
      # Embedding model
      embeddings = fetchModel {
        name = "all-minilm";
        source.huggingface.repo = "sentence-transformers/all-MiniLM-L6-v2";
        hash = "sha256-...";
      };

      # Text generation
      llama = fetchModel {
        name = "llama-2-7b";
        source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
        hash = "sha256-...";
        auth.tokenEnvVar = "HF_TOKEN";
      };

      # Classification
      classifier = fetchModel {
        name = "distilbert-sentiment";
        source.huggingface.repo = "distilbert-base-uncased-finetuned-sst-2-english";
        hash = "sha256-...";
      };
    };
  };
}
```

## Development Environment Flake

A flake with models and a development shell:

```nix
# flake.nix
{
  description = "ML Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nix-model-repo, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        fetchModel = nix-model-repo.lib.fetchModel pkgs;

        # Define models
        models = {
          bert = fetchModel {
            name = "bert-base";
            source.huggingface.repo = "google-bert/bert-base-uncased";
            hash = "sha256-...";
          };

          gpt2 = fetchModel {
            name = "gpt2";
            source.huggingface.repo = "openai-community/gpt2";
            hash = "sha256-...";
          };
        };

        # Python environment
        pythonEnv = pkgs.python311.withPackages (ps: [
          ps.transformers
          ps.torch
          ps.datasets
          ps.accelerate
          ps.jupyter
        ]);
      in {
        packages = models // {
          default = models.bert;
        };

        devShells.default = pkgs.mkShell {
          packages = [ pythonEnv ];

          shellHook = ''
            # Link models to HuggingFace cache
            mkdir -p ~/.cache/huggingface/hub

            ln -sfn ${models.bert} \
              ~/.cache/huggingface/hub/models--google-bert--bert-base-uncased

            ln -sfn ${models.gpt2} \
              ~/.cache/huggingface/hub/models--openai-community--gpt2

            # Enable offline mode
            export HF_HUB_OFFLINE=1
            export TRANSFORMERS_OFFLINE=1

            echo "Development environment ready!"
            echo "Models available: bert, gpt2"
          '';
        };
      }
    );
}
```

## Production Inference Flake

A flake for production deployment with strict validation:

```nix
# flake.nix
{
  description = "Production Inference Service";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { self, nixpkgs, nix-model-repo, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-model-repo.lib.fetchModel pkgs;
    presets = nix-model-repo.lib.validation.presets;
    validators = nix-model-repo.lib.validation.validators;
  in {
    packages.${system} = {
      # Production model with strict validation
      model = fetchModel {
        name = "mistral-7b-instruct";
        source.huggingface = {
          repo = "mistralai/Mistral-7B-Instruct-v0.2";
          # Only safetensors files
          files = [
            "config.json"
            "generation_config.json"
            "tokenizer.json"
            "tokenizer_config.json"
            "special_tokens_map.json"
            "model.safetensors.index.json"
            "model-00001-of-00003.safetensors"
            "model-00002-of-00003.safetensors"
            "model-00003-of-00003.safetensors"
          ];
        };
        hash = "sha256-...";

        # Strict security validation
        validation = presets.strict // {
          validators = presets.strict.validators ++ [
            (validators.maxSize "20G")
          ];
          timeout = 900;  # 15 min for thorough scan
        };

        # Network configuration
        network = {
          retry.maxAttempts = 5;
          timeout.read = 3600;  # 1 hour for large model
        };

        auth.tokenEnvVar = "HF_TOKEN";
      };
    };

    # NixOS module for deployment
    nixosModules.default = { config, ... }: {
      systemd.services.inference = {
        description = "Model Inference Service";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          HF_HOME = "/var/lib/inference/cache";
          HF_HUB_OFFLINE = "1";
          MODEL_PATH = "${self.packages.${system}.model}";
        };

        serviceConfig = {
          Type = "simple";
          User = "inference";
          Group = "inference";
          # Add your inference server command
        };
      };
    };
  };
}
```

## Multi-Source Flake

A flake using models from different sources:

```nix
# flake.nix
{
  description = "Multi-Source Models";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { self, nixpkgs, nix-model-repo, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-model-repo.lib.fetchModel pkgs;
    sources = nix-model-repo.lib.sources;

    # Create source factories
    companyS3 = sources.mkS3 {
      bucket = "company-ml-models";
      region = "us-west-2";
    };

    companyMLflow = sources.mkMlflow {
      trackingUri = "https://mlflow.company.internal";
    };
  in {
    packages.${system} = {
      # From HuggingFace
      public-bert = fetchModel {
        name = "bert-base";
        source.huggingface.repo = "google-bert/bert-base-uncased";
        hash = "sha256-...";
      };

      # From S3
      internal-classifier = fetchModel {
        name = "internal-classifier";
        source = companyS3 "classifiers/v2.1/";
        hash = "sha256-...";
        # Override HF integration for S3 model
        integration.huggingface = {
          enable = true;
          org = "company";
          model = "internal-classifier";
        };
      };

      # From MLflow
      production-model = fetchModel {
        name = "production-recommender";
        source = companyMLflow {
          name = "recommender";
          stage = "Production";
        };
        hash = "sha256-...";
        auth.tokenEnvVar = "MLFLOW_TOKEN";
      };

      # From Git LFS
      research-model = fetchModel {
        name = "research-experiment";
        source.git-lfs = {
          url = "https://github.com/company/ml-research.git";
          rev = "v0.5.0";
          subdir = "experiments/transformer";
        };
        hash = "sha256-...";
      };
    };
  };
}
```

## Validation Presets Flake

A flake demonstrating different validation configurations:

```nix
# flake.nix
{
  description = "Validation Examples";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { self, nixpkgs, nix-model-repo, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-model-repo.lib.fetchModel pkgs;
    presets = nix-model-repo.lib.validation.presets;
    validators = nix-model-repo.lib.validation.validators;
    mkValidator = nix-model-repo.lib.validation.mkValidator;

    # Custom validator
    requireReadme = mkValidator {
      name = "require-readme";
      description = "Ensure README exists";
      command = ''
        if [ ! -f "$src/README.md" ]; then
          echo "WARNING: No README.md found"
          exit 1
        fi
      '';
      onFailure = "warn";
    };
  in {
    packages.${system} = {
      # No validation (testing only!)
      quick-test = fetchModel {
        name = "test-model";
        source.huggingface.repo = "prajjwal1/bert-tiny";
        hash = "sha256-...";
        validation = presets.none;
      };

      # Minimal validation (development)
      dev-model = fetchModel {
        name = "dev-model";
        source.huggingface.repo = "distilbert-base-uncased";
        hash = "sha256-...";
        validation = presets.minimal;
      };

      # Standard validation (default)
      standard-model = fetchModel {
        name = "standard-model";
        source.huggingface.repo = "google-bert/bert-base-uncased";
        hash = "sha256-...";
        validation = presets.standard;
      };

      # Strict validation (production)
      secure-model = fetchModel {
        name = "secure-model";
        source.huggingface.repo = "mistralai/Mistral-7B-v0.1";
        hash = "sha256-...";
        validation = presets.strict;
      };

      # Custom validation
      custom-model = fetchModel {
        name = "custom-validated";
        source.huggingface.repo = "org/model";
        hash = "sha256-...";
        validation = {
          enable = true;
          validators = [
            validators.noPickleFiles
            validators.safetensorsOnly
            (validators.maxSize "5G")
            (validators.requiredFiles [ "config.json" "tokenizer.json" ])
            requireReadme
          ];
          onFailure = "abort";
          timeout = 600;
        };
      };
    };
  };
}
```

## NixOS Configuration with Models

A complete NixOS configuration with AI models:

```nix
# flake.nix
{
  description = "NixOS with AI Models";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { self, nixpkgs, nix-model-repo, ... }: {
    nixosConfigurations.ai-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-model-repo.nixosModules.default
        ({ config, pkgs, ... }: {
          # System configuration
          networking.hostName = "ai-server";

          # AI Models configuration
          services.model-repo = {
            enable = true;

            models = {
              llama-2-7b = {
                source.huggingface.repo = "meta-llama/Llama-2-7b-chat-hf";
                hash = "sha256-...";
              };
              embeddings = {
                source.huggingface.repo = "sentence-transformers/all-MiniLM-L6-v2";
                hash = "sha256-...";
              };
            };

            integration.huggingface = {
              enable = true;
              cacheDir = "/var/lib/model-repo/cache";
            };

            auth.tokenFile = "/run/secrets/hf-token";
          };

          # Users who can access models
          users.groups.model-repo = {};
          users.users.inference = {
            isSystemUser = true;
            group = "model-repo";
          };

          # Inference service example
          systemd.services.inference-api = {
            description = "AI Inference API";
            after = [ "model-repo.service" "network.target" ];
            wantedBy = [ "multi-user.target" ];

            environment = {
              HF_HOME = "/var/lib/model-repo/cache";
              HF_HUB_OFFLINE = "1";
            };

            serviceConfig = {
              Type = "simple";
              User = "inference";
              Group = "model-repo";
              ExecStart = "${pkgs.python3}/bin/python -m my_inference_server";
            };
          };
        })
      ];
    };
  };
}
```

## Home Manager Configuration

A Home Manager configuration with AI models:

```nix
# flake.nix
{
  description = "Home Manager with AI Models";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  outputs = { self, nixpkgs, home-manager, nix-model-repo, ... }: {
    homeConfigurations.developer = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        nix-model-repo.homeManagerModules.default
        ({ config, pkgs, ... }: {
          home.username = "developer";
          home.homeDirectory = "/home/developer";
          home.stateVersion = "24.05";

          # AI Models
          programs.model-repo = {
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
            integration.huggingface.enable = true;
          };

          # Development packages
          home.packages = with pkgs; [
            (python311.withPackages (ps: [
              ps.transformers
              ps.torch
              ps.jupyter
            ]))
          ];

          # Shell configuration
          programs.zsh = {
            enable = true;
            shellAliases = {
              ml-offline = "export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1";
              ml-online = "unset HF_HUB_OFFLINE TRANSFORMERS_OFFLINE";
            };
          };

          # Environment variables
          home.sessionVariables = {
            HF_HUB_OFFLINE = "1";
          };
        })
      ];
    };
  };
}
```

## Devenv Configuration

A [devenv](https://devenv.sh) configuration with AI models. See the full [Devenv Integration Guide](devenv.md) for more details.

### Basic Devenv Setup

**devenv.yaml:**
```yaml
inputs:
  nix-model-repo:
    url: github:parthspatel/nix-model-repo
```

**devenv.nix:**
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

      gpt2 = {
        source.huggingface.repo = "openai-community/gpt2";
        hash = "sha256-...";
      };
    };
  };

  # Python environment
  languages.python = {
    enable = true;
    package = pkgs.python311;
  };

  packages = [
    pkgs.python311Packages.transformers
    pkgs.python311Packages.torch
  ];
}
```

### ML Development with Devenv

A complete ML development environment:

```nix
# devenv.nix
{ pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.nix-model-repo.devenvModules.default
  ];

  # AI Models with different configurations
  services.model-repo = {
    enable = true;

    models = {
      # Small model for quick iteration
      bert-tiny = {
        source.huggingface.repo = "prajjwal1/bert-tiny";
        hash = "sha256-...";
        validation.enable = false;  # Skip for speed
      };

      # Production embedding model
      embeddings = {
        source.huggingface.repo = "sentence-transformers/all-MiniLM-L6-v2";
        hash = "sha256-...";
      };

      # Large model (gated, requires auth)
      llama = {
        source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
        hash = "sha256-...";
        auth.tokenEnvVar = "HF_TOKEN";
      };
    };

    # Custom cache location
    cacheDir = ".cache/models";

    # Offline mode (recommended)
    offlineMode = true;
  };

  # Python with ML stack
  languages.python = {
    enable = true;
    package = pkgs.python311;
    venv = {
      enable = true;
      requirements = ''
        transformers
        torch
        datasets
        accelerate
        jupyter
        matplotlib
        pandas
      '';
    };
  };

  # Additional tools
  packages = with pkgs; [
    jq
    curl
  ];

  # Custom scripts
  scripts = {
    train.exec = ''
      python scripts/train.py "$@"
    '';

    evaluate.exec = ''
      python scripts/evaluate.py "$@"
    '';

    notebook.exec = ''
      jupyter lab --no-browser
    '';
  };

  # Pre-commit hooks
  pre-commit.hooks = {
    black.enable = true;
    ruff.enable = true;
  };

  # Shell startup
  enterShell = ''
    echo "🤖 ML Development Environment"
    echo ""
    echo "Available models:"
    echo "  - bert-tiny (fast iteration)"
    echo "  - embeddings (sentence-transformers)"
    echo "  - llama (requires HF_TOKEN)"
    echo ""
    echo "Commands:"
    echo "  train      - Run training script"
    echo "  evaluate   - Run evaluation"
    echo "  notebook   - Start Jupyter Lab"
  '';
}
```

### Devenv with Flakes

Using devenv with a flake for more control:

```nix
# flake.nix
{
  description = "ML Project with Devenv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    nix-model-repo.url = "github:parthspatel/nix-model-repo";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, devenv, nix-model-repo, ... }@inputs:
  let
    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forEachSystem = nixpkgs.lib.genAttrs systems;
  in {
    packages = forEachSystem (system: {
      devenv-up = self.devShells.${system}.default.config.procfileScript;
    });

    devShells = forEachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = devenv.lib.mkShell {
          inherit inputs pkgs;

          modules = [
            nix-model-repo.devenvModules.default
            {
              services.model-repo = {
                enable = true;
                models = {
                  bert = {
                    source.huggingface.repo = "google-bert/bert-base-uncased";
                    hash = "sha256-...";
                  };
                };
              };

              languages.python.enable = true;

              packages = with pkgs; [
                python311Packages.transformers
              ];
            }
          ];
        };
      }
    );
  };
}
```

### Devenv without Module

If you prefer not to use the module, you can use the library directly:

```nix
# devenv.nix
{ pkgs, lib, inputs, ... }:

let
  fetchModel = inputs.nix-model-repo.lib.fetchModel pkgs;

  # Define models
  bert = fetchModel {
    name = "bert-base";
    source.huggingface.repo = "google-bert/bert-base-uncased";
    hash = "sha256-...";
  };

  gpt2 = fetchModel {
    name = "gpt2";
    source.huggingface.repo = "openai-community/gpt2";
    hash = "sha256-...";
  };
in {
  # Make models available as packages
  packages = [ bert gpt2 ];

  # Set environment variables
  env = {
    BERT_MODEL = "${bert}";
    GPT2_MODEL = "${gpt2}";
    HF_HUB_OFFLINE = "1";
    TRANSFORMERS_OFFLINE = "1";
  };

  # Setup HuggingFace cache
  enterShell = ''
    mkdir -p .cache/huggingface/hub

    # Link models to HF cache
    ln -sfn ${bert} .cache/huggingface/hub/models--google-bert--bert-base-uncased
    ln -sfn ${gpt2} .cache/huggingface/hub/models--openai-community--gpt2

    export HF_HOME="$PWD/.cache/huggingface"

    echo "Models linked to .cache/huggingface/hub/"
    echo "  - bert: $BERT_MODEL"
    echo "  - gpt2: $GPT2_MODEL"
  '';
}
```
