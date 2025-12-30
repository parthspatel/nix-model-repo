# modules/home-manager.nix
# Home Manager module for AI model management
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.model-repo;

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

            Example:
              source.huggingface.repo = "google-bert/bert-base-uncased";
          '';
          example = {
            huggingface = {
              repo = "google-bert/bert-base-uncased";
              revision = "main";
            };
          };
        };

        hash = lib.mkOption {
          type = lib.types.str;
          description = "SRI hash of the model (sha256-...)";
          example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        };

        validation = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Validation configuration for the model";
        };

        integration = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Integration configuration (e.g., huggingface cache setup)";
        };

        network = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Network configuration (timeouts, retries, proxy)";
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
      inherit (modelCfg)
        name
        source
        hash
        validation
        integration
        network
        auth
        meta
        ;
    };

  # All enabled models as derivations
  modelDerivations = lib.mapAttrs buildModel cfg.models;

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

  # Generate setup script for HuggingFace cache symlinks
  mkHfSetupScript =
    models:
    let
      hfModels = lib.filterAttrs (
        _: m: m.source ? huggingface || (m.integration.huggingface.enable or false)
      ) models;

      setupCommands = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: modelCfg:
          let
            drv = modelDerivations.${name};
            parsed = parseHfRepo modelCfg.source.huggingface.repo;
            linkPath = "$HF_HOME/hub/models--${parsed.org}--${parsed.model}";
          in
          ''
            # Setup ${name}
            if [[ -L "${linkPath}" ]]; then
              rm "${linkPath}"
            elif [[ -e "${linkPath}" ]]; then
              echo "Warning: ${linkPath} exists and is not a symlink, skipping" >&2
            fi
            if [[ ! -e "${linkPath}" ]]; then
              mkdir -p "$(dirname "${linkPath}")"
              ln -s "${drv}" "${linkPath}"
              echo "Linked: ${parsed.org}/${parsed.model} -> ${drv}"
            fi
          ''
        ) hfModels
      );
    in
    pkgs.writeShellScript "setup-hf-models" ''
      set -euo pipefail
      export HF_HOME="''${HF_HOME:-$HOME/.cache/huggingface}"
      mkdir -p "$HF_HOME/hub"
      ${setupCommands}
    '';

in
{
  options.programs.model-repo = {
    enable = lib.mkEnableOption "AI model management for user";

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule modelOpts);
      default = { };
      description = "AI models to manage";
      example = lib.literalExpression ''
        {
          bert-base-uncased = {
            source.huggingface.repo = "google-bert/bert-base-uncased";
            hash = "sha256-...";
          };
        }
      '';
    };

    integration = {
      huggingface = {
        enable = lib.mkEnableOption "HuggingFace cache integration";

        cacheDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Custom HuggingFace cache directory (defaults to ~/.cache/huggingface)";
        };

        offlineMode = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable offline mode environment variables";
        };

        setupOnActivation = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Setup HuggingFace cache symlinks on home-manager activation";
        };
      };
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
    # Add model derivations to user packages (ensures they're built)
    home.packages = lib.attrValues modelDerivations;

    # Setup HuggingFace cache on activation
    home.activation.setupModelRepoHfCache =
      lib.mkIf
        (
          cfg.integration.huggingface.enable
          && cfg.integration.huggingface.setupOnActivation
          && cfg.models != { }
        )
        (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${mkHfSetupScript cfg.models}
          ''
        );

    # Set environment variables for offline mode
    home.sessionVariables =
      lib.mkIf (cfg.integration.huggingface.enable && cfg.integration.huggingface.offlineMode)
        {
          HF_HUB_OFFLINE = "1";
          TRANSFORMERS_OFFLINE = "1";
        };
  };
}
