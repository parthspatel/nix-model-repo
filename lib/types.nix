# lib/types.nix
# Type definitions and validation for fetchModel configuration
{ lib }:

let
  inherit (lib) hasAttr isString isList isAttrs all length filter head;
  inherit (builtins) attrNames;

  # Known source types
  knownSourceTypes = [
    "huggingface"
    "mlflow"
    "s3"
    "git-lfs"
    "git-xet"
    "url"
    "ollama"
    "mock"  # For testing
  ];

  # Validation helpers
  isNonEmptyString = x: isString x && x != "";
  isOptionalString = x: x == null || isString x;
  isOptionalList = x: x == null || isList x;

  # Validate HuggingFace source config
  validateHuggingface = cfg:
    let
      errors = []
        ++ (if !(hasAttr "repo" cfg) then [ "huggingface: 'repo' is required" ] else [])
        ++ (if hasAttr "repo" cfg && !(isNonEmptyString cfg.repo) then [ "huggingface: 'repo' must be a non-empty string" ] else [])
        ++ (if hasAttr "repo" cfg && isString cfg.repo && !(lib.hasInfix "/" cfg.repo) then [ "huggingface: 'repo' must be in 'org/model' format" ] else [])
        ++ (if hasAttr "revision" cfg && !(isNonEmptyString cfg.revision) then [ "huggingface: 'revision' must be a non-empty string" ] else [])
        ++ (if hasAttr "files" cfg && !(isOptionalList cfg.files) then [ "huggingface: 'files' must be a list of strings or null" ] else []);
    in {
      valid = errors == [];
      inherit errors;
    };

  # Validate MLFlow source config
  validateMlflow = cfg:
    let
      errors = []
        ++ (if !(hasAttr "trackingUri" cfg) then [ "mlflow: 'trackingUri' is required" ] else [])
        ++ (if !(hasAttr "modelName" cfg) then [ "mlflow: 'modelName' is required" ] else [])
        ++ (if hasAttr "modelVersion" cfg && hasAttr "modelStage" cfg && cfg.modelVersion != null && cfg.modelStage != null
            then [ "mlflow: specify either 'modelVersion' or 'modelStage', not both" ] else []);
    in {
      valid = errors == [];
      inherit errors;
    };

  # Validate S3 source config
  validateS3 = cfg:
    let
      errors = []
        ++ (if !(hasAttr "bucket" cfg) then [ "s3: 'bucket' is required" ] else [])
        ++ (if !(hasAttr "prefix" cfg) then [ "s3: 'prefix' is required" ] else [])
        ++ (if !(hasAttr "region" cfg) then [ "s3: 'region' is required" ] else []);
    in {
      valid = errors == [];
      inherit errors;
    };

  # Validate Git LFS source config
  validateGitLfs = cfg:
    let
      errors = []
        ++ (if !(hasAttr "url" cfg) then [ "git-lfs: 'url' is required" ] else [])
        ++ (if !(hasAttr "rev" cfg) then [ "git-lfs: 'rev' is required" ] else []);
    in {
      valid = errors == [];
      inherit errors;
    };

  # Validate Git-Xet source config
  validateGitXet = cfg:
    let
      errors = []
        ++ (if !(hasAttr "url" cfg) then [ "git-xet: 'url' is required" ] else [])
        ++ (if !(hasAttr "rev" cfg) then [ "git-xet: 'rev' is required" ] else []);
    in {
      valid = errors == [];
      inherit errors;
    };

  # Validate URL source config
  validateUrl = cfg:
    let
      errors = []
        ++ (if !(hasAttr "urls" cfg) then [ "url: 'urls' is required" ] else [])
        ++ (if hasAttr "urls" cfg && !(isList cfg.urls) then [ "url: 'urls' must be a list" ] else [])
        ++ (if hasAttr "urls" cfg && isList cfg.urls && cfg.urls == [] then [ "url: 'urls' must not be empty" ] else []);
    in {
      valid = errors == [];
      inherit errors;
    };

  # Validate Ollama source config
  validateOllama = cfg:
    let
      errors = []
        ++ (if !(hasAttr "model" cfg) then [ "ollama: 'model' is required" ] else [])
        ++ (if hasAttr "model" cfg && !(isNonEmptyString cfg.model) then [ "ollama: 'model' must be a non-empty string" ] else []);
    in {
      valid = errors == [];
      inherit errors;
    };

  # Source validator dispatch
  # Validate mock source config (for testing)
  validateMock = _cfg: {
    valid = true;
    errors = [];
  };

  sourceValidators = {
    huggingface = validateHuggingface;
    mlflow = validateMlflow;
    s3 = validateS3;
    "git-lfs" = validateGitLfs;
    "git-xet" = validateGitXet;
    url = validateUrl;
    ollama = validateOllama;
    mock = validateMock;
  };

in {
  # List of known source types
  inherit knownSourceTypes;

  # Validate a source configuration
  # Returns: { valid: bool, errors: [string], sourceType: string | null }
  validateSource = sourceConfig:
    let
      # Find which source types are specified
      specifiedTypes = filter (t: hasAttr t sourceConfig) knownSourceTypes;
      numTypes = length specifiedTypes;
    in
      if !isAttrs sourceConfig then {
        valid = false;
        errors = [ "source must be an attribute set" ];
        sourceType = null;
      }
      else if numTypes == 0 then {
        valid = false;
        errors = [ "source must specify exactly one of: ${lib.concatStringsSep ", " knownSourceTypes}" ];
        sourceType = null;
      }
      else if numTypes > 1 then {
        valid = false;
        errors = [ "source must specify exactly one type, got: ${lib.concatStringsSep ", " specifiedTypes}" ];
        sourceType = null;
      }
      else
        let
          sourceType = head specifiedTypes;
          validator = sourceValidators.${sourceType};
          result = validator sourceConfig.${sourceType};
        in {
          inherit (result) valid errors;
          inherit sourceType;
        };

  # Validate the full fetchModel configuration
  # Returns: { valid: bool, errors: [string] }
  validateConfig = config:
    let
      # Required field checks
      requiredErrors = []
        ++ (if !(hasAttr "name" config) then [ "'name' is required" ] else [])
        ++ (if hasAttr "name" config && !(isNonEmptyString config.name) then [ "'name' must be a non-empty string" ] else [])
        ++ (if !(hasAttr "source" config) then [ "'source' is required" ] else [])
        ++ (if !(hasAttr "hash" config) then [ "'hash' is required" ] else [])
        ++ (if hasAttr "hash" config && !(isNonEmptyString config.hash) then [ "'hash' must be a non-empty string" ] else []);

      # Source validation
      sourceResult = if hasAttr "source" config then validateSource config.source else { valid = true; errors = []; };

      # Combine all errors
      allErrors = requiredErrors ++ sourceResult.errors;
    in {
      valid = allErrors == [];
      errors = allErrors;
      sourceType = sourceResult.sourceType or null;
    };

  # Normalize a hash to SRI format
  # Supports: sha256-xxx, sha256:xxx, or raw hex
  normalizeHash = hash:
    if lib.hasPrefix "sha256-" hash then
      hash
    else if lib.hasPrefix "sha256:" hash then
      "sha256-${lib.removePrefix "sha256:" hash}"
    else if lib.stringLength hash == 64 then
      # Assume raw hex, convert to base64
      # For now, just prefix it - proper conversion would need more work
      "sha256-${hash}"
    else
      hash;

  # Extract hash algorithm from SRI hash
  hashAlgo = hash:
    if lib.hasPrefix "sha256-" hash then "sha256"
    else if lib.hasPrefix "sha512-" hash then "sha512"
    else "sha256";

  # Validation defaults
  defaultValidation = {
    enable = true;
    skipDefaults = false;
    validators = [];
    onFailure = "abort";
    timeout = 300;
    defaults = {
      modelscan = true;
      pickleScan = true;
      checksums = true;
    };
  };

  # Network defaults
  defaultNetwork = {
    timeout = {
      connect = 30;
      read = 300;
    };
    retry = {
      maxAttempts = 3;
      baseDelay = 2;
    };
    bandwidth = {
      limit = null;
    };
    proxy = null;
  };

  # Merge user config with defaults
  mergeWithDefaults = config: {
    name = config.name;
    source = config.source;
    hash = normalizeHash config.hash;
    validation = defaultValidation // (config.validation or {});
    network = lib.recursiveUpdate defaultNetwork (config.network or {});
    auth = config.auth or {};
    integration = config.integration or {
      huggingface.enable = true;
    };
    meta = config.meta or {};
  };
}
