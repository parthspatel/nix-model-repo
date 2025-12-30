# modules/devenv.nix
# Devenv module for nix-model-repo
# Usage: Import this module and configure services.model-repo
{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.services.model-repo;

  # Import our library
  modelRepoLib = import ../lib {
    inherit lib pkgs;
  };

  # Model configuration type
  modelOpts =
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Name of the model (defaults to attribute name)";
        };

        source = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          description = ''
            Source configuration for the model.
            Supports: huggingface, mlflow, s3, git-lfs, git-xet, url, ollama.
          '';
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
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Validation configuration";
        };

        integration = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Integration configuration";
        };

        network = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Network configuration";
        };

        auth = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Authentication configuration";
        };

        meta = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Metadata for the model";
        };
      };
    };

  # Build a model derivation from config
  buildModel =
    name: modelCfg:
    modelRepoLib.fetchModel {
      inherit name;
      inherit (modelCfg)
        source
        hash
        validation
        integration
        network
        auth
        meta
        ;
    };

  # All built models
  builtModels = lib.mapAttrs buildModel cfg.models;

  # Parse HuggingFace repo to get org/model
  parseHfRepo =
    repo:
    let
      parts = lib.splitString "/" repo;
    in
    {
      org = lib.elemAt parts 0;
      model = lib.elemAt parts 1;
    };

  # Generate HF cache path from model config
  getHfCachePath =
    modelCfg:
    if modelCfg.source ? huggingface then
      let
        parsed = parseHfRepo modelCfg.source.huggingface.repo;
      in
      "models--${parsed.org}--${parsed.model}"
    else
      null;

in
{
  options.services.model-repo = {
    enable = lib.mkEnableOption "AI model management";

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule modelOpts);
      default = { };
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
      default = ".devenv/model-repo";
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

    globalValidation = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Default validation settings applied to all models";
    };

    globalNetwork = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Default network settings applied to all models";
    };
  };

  config = lib.mkIf cfg.enable {
    # Add model paths as environment variables
    env =
      lib.mapAttrs' (
        name: model:
        lib.nameValuePair "MODEL_REPO_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name)}" "${model}"
      ) builtModels
      // lib.optionalAttrs cfg.offlineMode {
        HF_HUB_OFFLINE = "1";
        TRANSFORMERS_OFFLINE = "1";
      };

    # Create cache directory and symlinks
    enterShell = lib.mkIf cfg.linkToHuggingFace ''
      # Setup HuggingFace cache symlinks
      _model_repo_cache="${cfg.cacheDir}"
      mkdir -p "$_model_repo_cache"

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: modelCfg:
          let
            model = builtModels.${name};
            cachePath = getHfCachePath modelCfg;
          in
          if cachePath != null then
            ''
              # Link ${name}
              if [ -d "${model}" ]; then
                ln -sfn "${model}" "$_model_repo_cache/${cachePath}"
                echo "Linked ${name} -> ${cachePath}"
              fi
            ''
          else
            ''
              # ${name}: Not a HuggingFace model, skipping symlink
              echo "Model ${name}: available at ${model}"
            ''
        ) cfg.models
      )}

      export HF_HOME="$_model_repo_cache"
      echo ""
      echo "AI Models available:"
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: model: ''
          echo "  ${name}: ${model}"
        '') builtModels
      )}
    '';

    # Expose models in packages for direct access
    packages = lib.attrValues builtModels;
  };
}
