# modules/nixos.nix
# NixOS module for system-wide AI model management
{
  config,
  lib,
  pkgs,
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

  # Get HuggingFace models only
  hfModels = lib.filterAttrs (_: m: m.source ? huggingface) cfg.models;

  # Generate setup script for HuggingFace cache symlinks
  setupScript = pkgs.writeShellScript "setup-model-repo" ''
    set -euo pipefail

    CACHE_DIR="${cfg.integration.huggingface.cacheDir}"
    mkdir -p "$CACHE_DIR/hub"

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: modelCfg:
        let
          drv = modelDerivations.${name};
          parsed = parseHfRepo modelCfg.source.huggingface.repo;
          linkPath = "$CACHE_DIR/hub/models--${parsed.org}--${parsed.model}";
        in
        ''
          # Setup ${name}
          if [[ -L "${linkPath}" ]]; then
            rm "${linkPath}"
          elif [[ -e "${linkPath}" ]]; then
            echo "Warning: ${linkPath} exists and is not a symlink, skipping" >&2
          fi
          if [[ ! -e "${linkPath}" ]]; then
            ln -s "${drv}" "${linkPath}"
            echo "Linked: ${parsed.org}/${parsed.model} -> ${drv}"
          fi
        ''
      ) hfModels
    )}

    # Set permissions
    chown -R ${cfg.user}:${cfg.group} "$CACHE_DIR"
    chmod -R g+rX "$CACHE_DIR"

    echo "Model repository setup complete."
  '';

in
{
  options.services.model-repo = {
    enable = lib.mkEnableOption "AI model management service";

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule modelOpts);
      default = { };
      description = "AI models to manage system-wide";
      example = lib.literalExpression ''
        {
          llama-2-7b = {
            source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
            hash = "sha256-...";
          };
          bert-base = {
            source.huggingface.repo = "google-bert/bert-base-uncased";
            hash = "sha256-...";
          };
        }
      '';
    };

    integration = {
      huggingface = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Create HuggingFace-compatible cache structure";
        };

        cacheDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/cache/huggingface";
          description = "Directory for HuggingFace cache structure";
        };
      };
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User that owns the model cache directory";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "model-repo";
      description = "Group with read access to models";
    };

    createGroup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create the model-repo group";
    };

    auth = {
      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing HuggingFace token (for gated models)";
        example = "/run/secrets/hf-token";
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

    # Read-only: expose model paths for use in other configs
    modelPaths = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      readOnly = true;
      description = "Attribute set of model names to their store paths (read-only)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Expose model paths for use in other configuration
    services.model-repo.modelPaths = modelDerivations;

    # Create the group if requested
    users.groups = lib.mkIf cfg.createGroup {
      ${cfg.group} = { };
    };

    # Systemd service to set up the model cache
    systemd.services.model-repo = {
      description = "AI Model Repository Setup";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];

      # Only run when models are configured
      unitConfig.ConditionPathExists = lib.mkIf (cfg.models != { }) "!";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = setupScript;

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.integration.huggingface.cacheDir ];
      };

      # Set HF_TOKEN if tokenFile is provided
      environment = lib.mkIf (cfg.auth.tokenFile != null) {
        HF_TOKEN_FILE = cfg.auth.tokenFile;
      };
    };

    # Create cache directory with correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.integration.huggingface.cacheDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.integration.huggingface.cacheDir}/hub 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Environment variables for system services
    environment.variables = lib.mkIf cfg.integration.huggingface.enable {
      HF_HOME = cfg.integration.huggingface.cacheDir;
    };

    # Add models to system packages (ensures they're built)
    environment.systemPackages = lib.attrValues modelDerivations;
  };
}
