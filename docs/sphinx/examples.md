# Example Flakes

This page provides complete example flake configurations for common use cases.

## Basic Model Flake

A minimal flake that fetches a single model:

```nix
# flake.nix
{
  description = "My AI Model";

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
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { self, nixpkgs, nix-ai-models, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-ai-models.lib.fetchModel pkgs;
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
    nix-ai-models.url = "github:your-org/nix-ai-models";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nix-ai-models, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        fetchModel = nix-ai-models.lib.fetchModel pkgs;

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
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { self, nixpkgs, nix-ai-models, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-ai-models.lib.fetchModel pkgs;
    presets = nix-ai-models.lib.validation.presets;
    validators = nix-ai-models.lib.validation.validators;
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
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { self, nixpkgs, nix-ai-models, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-ai-models.lib.fetchModel pkgs;
    sources = nix-ai-models.lib.sources;

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
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { self, nixpkgs, nix-ai-models, ... }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    fetchModel = nix-ai-models.lib.fetchModel pkgs;
    presets = nix-ai-models.lib.validation.presets;
    validators = nix-ai-models.lib.validation.validators;
    mkValidator = nix-ai-models.lib.validation.mkValidator;

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
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { self, nixpkgs, nix-ai-models, ... }: {
    nixosConfigurations.ai-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-ai-models.nixosModules.default
        ({ config, pkgs, ... }: {
          # System configuration
          networking.hostName = "ai-server";

          # AI Models configuration
          services.ai-models = {
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
              cacheDir = "/var/lib/ai-models/cache";
            };

            auth.tokenFile = "/run/secrets/hf-token";
          };

          # Users who can access models
          users.groups.ai-models = {};
          users.users.inference = {
            isSystemUser = true;
            group = "ai-models";
          };

          # Inference service example
          systemd.services.inference-api = {
            description = "AI Inference API";
            after = [ "ai-models.service" "network.target" ];
            wantedBy = [ "multi-user.target" ];

            environment = {
              HF_HOME = "/var/lib/ai-models/cache";
              HF_HUB_OFFLINE = "1";
            };

            serviceConfig = {
              Type = "simple";
              User = "inference";
              Group = "ai-models";
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
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { self, nixpkgs, home-manager, nix-ai-models, ... }: {
    homeConfigurations.developer = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        nix-ai-models.homeManagerModules.default
        ({ config, pkgs, ... }: {
          home.username = "developer";
          home.homeDirectory = "/home/developer";
          home.stateVersion = "24.05";

          # AI Models
          programs.ai-models = {
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
