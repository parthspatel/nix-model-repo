# lib/sources/huggingface.nix
# HuggingFace Hub source adapter
{ lib, pkgs }:

let
  # Path to fetcher scripts (relative to flake root)
  fetcherScript = ../../fetchers/huggingface.sh;
  commonScript = ../../fetchers/common.sh;

in {
  # Source type identifier
  sourceType = "huggingface";

  # Build the FOD derivation for fetching from HuggingFace
  mkFetchDerivation = {
    name,
    hash,
    sourceConfig,
    auth ? {},
    network ? {},
  }:
    let
      # Extract config with defaults
      repo = sourceConfig.repo;
      revision = sourceConfig.revision or "main";
      files = sourceConfig.files or null;

      # Convert files list to space-separated string for shell
      filesArg = if files == null then "" else lib.concatStringsSep " " files;

      # Network settings with defaults
      connectTimeout = toString (network.timeout.connect or 30);
      maxTime = toString (network.timeout.read or 0);  # 0 = no limit
      bandwidthLimit = network.bandwidth.limit or "";

      # Determine derivation name from repo
      drvName = "${lib.replaceStrings ["/"] ["-"] repo}-raw";

    in pkgs.stdenvNoCC.mkDerivation {
      name = drvName;

      # Fixed-output derivation settings
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      outputHash = hash;

      # No source - we're fetching from network
      dontUnpack = true;

      # Build dependencies
      nativeBuildInputs = with pkgs; [
        curl
        jq
        cacert
        coreutils
      ];

      # Impure environment variables for authentication
      # These are read from the build environment (user's shell)
      impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
        "HF_TOKEN"
        "HUGGING_FACE_HUB_TOKEN"
      ] ++ lib.optionals (auth.tokenEnvVar or null != null) [
        auth.tokenEnvVar
      ];

      # Environment variables for the fetcher script
      REPO = repo;
      REVISION = revision;
      FILES = filesArg;
      SOURCE_TYPE = "huggingface";

      # Network configuration
      CONNECT_TIMEOUT = connectTimeout;
      MAX_TIME = maxTime;
      BANDWIDTH_LIMIT = bandwidthLimit;

      # SSL certificates
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

      # Builder script
      buildPhase = ''
        runHook preBuild

        # Source common utilities
        source ${commonScript}

        # Run the HuggingFace fetcher
        source ${fetcherScript}

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        # Fetcher script writes directly to $out
        runHook postInstall
      '';

      # Useful metadata
      passthru = {
        inherit repo revision;
        sourceType = "huggingface";
      };

      meta = {
        description = "HuggingFace model: ${repo}";
      };
    };

  # Validate HuggingFace-specific configuration
  validateConfig = sourceConfig:
    let
      errors = []
        ++ (if !(sourceConfig ? repo) then ["'repo' is required"] else [])
        ++ (if sourceConfig ? repo && !(lib.isString sourceConfig.repo) then ["'repo' must be a string"] else [])
        ++ (if sourceConfig ? repo && lib.isString sourceConfig.repo && !(lib.hasInfix "/" sourceConfig.repo)
            then ["'repo' must be in 'org/model' format"] else [])
        ++ (if sourceConfig ? revision && !(lib.isString sourceConfig.revision) then ["'revision' must be a string"] else [])
        ++ (if sourceConfig ? files && !(lib.isList sourceConfig.files) then ["'files' must be a list"] else []);
    in {
      valid = errors == [];
      inherit errors;
    };

  # Impure environment variables this source needs
  impureEnvVars = _sourceConfig: [
    "HF_TOKEN"
    "HUGGING_FACE_HUB_TOKEN"
  ];

  # Build dependencies
  buildInputs = pkgs: with pkgs; [
    curl
    jq
    cacert
    coreutils
  ];

  # Extract metadata from source config
  extractMeta = sourceConfig:
    let
      parts = lib.splitString "/" sourceConfig.repo;
      org = lib.elemAt parts 0;
      model = lib.elemAt parts 1;
    in {
      inherit org model;
      revision = sourceConfig.revision or "main";
      sourceType = "huggingface";
      repo = sourceConfig.repo;
    };
}
