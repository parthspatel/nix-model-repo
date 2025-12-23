# modules/devenv.nix
# Devenv module for nix-ai-models
# Usage: Import this module and configure services.ai-models
{ lib, pkgs, config, ... }:

let
  cfg = config.services.ai-models;

  # Import our library
  fetchModel = import ../lib/fetchModel.nix {
    inherit lib pkgs;
    types = import ../lib/types.nix { inherit lib; };
    sources = import ../lib/sources { inherit lib pkgs; };
    validation = import ../lib/validation { inherit lib pkgs; };
  };

  # Build a model from config
  buildModel = name: modelCfg:
    fetchModel (modelCfg // { inherit name; });

  # All built models
  builtModels = lib.mapAttrs buildModel cfg.models;

in {
  options.services.ai-models = {
    enable = lib.mkEnableOption "AI model management";

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          source = lib.mkOption {
            type = lib.types.attrs;
            description = "Model source configuration";
            example = lib.literalExpression ''
              { huggingface.repo = "google-bert/bert-base-uncased"; }
            '';
          };

          hash = lib.mkOption {
            type = lib.types.str;
            description = "SHA256 hash of the model (SRI format)";
            example = "sha256-abc123...";
          };

          validation = lib.mkOption {
            type = lib.types.attrs;
            default = {};
            description = "Validation configuration";
          };

          auth = lib.mkOption {
            type = lib.types.attrs;
            default = {};
            description = "Authentication configuration";
          };
        };
      });
      default = {};
      description = "AI models to fetch and manage";
      example = lib.literalExpression ''
        {
          bert = {
            source.huggingface.repo = "google-bert/bert-base-uncased";
            hash = "sha256-...";
          };
          llama = {
            source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
            hash = "sha256-...";
            auth.tokenEnvVar = "HF_TOKEN";
          };
        }
      '';
    };

    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = ".devenv/ai-models";
      description = "Directory for HuggingFace cache symlinks";
    };

    linkToHuggingFace = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create symlinks in HuggingFace cache directory";
    };

    offlineMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set HF_HUB_OFFLINE after models are linked";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add model paths as environment variables
    env = lib.mapAttrs'
      (name: model: lib.nameValuePair "AI_MODEL_${lib.toUpper name}" "${model}")
      builtModels;

    # Set HuggingFace offline mode
    env.HF_HUB_OFFLINE = lib.mkIf cfg.offlineMode "1";
    env.TRANSFORMERS_OFFLINE = lib.mkIf cfg.offlineMode "1";

    # Create cache directory and symlinks
    enterShell = lib.mkIf cfg.linkToHuggingFace ''
      # Setup HuggingFace cache symlinks
      _ai_models_cache="${cfg.cacheDir}"
      mkdir -p "$_ai_models_cache"

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: model: ''
        # Link ${name}
        if [ -d "${model}" ]; then
          _cache_name="${model.passthru.hfCachePath or "models--unknown--${name}"}"
          ln -sfn "${model}" "$_ai_models_cache/$_cache_name"
          echo "Linked ${name} -> $_cache_name"
        fi
      '') builtModels)}

      export HF_HOME="$_ai_models_cache"
      echo ""
      echo "AI Models available:"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: model: ''
        echo "  ${name}: ${model}"
      '') builtModels)}
    '';

    # Expose models in packages for direct access
    packages = lib.attrValues builtModels;
  };
}
