# lib/sources/mlflow.nix
# MLflow Model Registry source adapter
{ lib, pkgs }:

let
  # Path to fetcher scripts (relative to flake root)
  fetcherScript = ../../fetchers/mlflow.sh;
  commonScript = ../../fetchers/common.sh;

in
{
  # Source type identifier
  sourceType = "mlflow";

  # Build the FOD derivation for fetching from MLflow
  mkFetchDerivation =
    {
      name,
      hash,
      sourceConfig,
      auth ? { },
      network ? { },
    }:
    let
      # Extract config with defaults
      trackingUri = sourceConfig.trackingUri;
      modelName = sourceConfig.modelName;
      modelVersion = sourceConfig.modelVersion or null;
      modelStage = sourceConfig.modelStage or null;

      # Network settings with defaults
      connectTimeout = toString (network.timeout.connect or 30);
      maxTime = toString (network.timeout.read or 0); # 0 = no limit

      # Create a safe derivation name
      safeName = lib.replaceStrings [ "/" ] [ "-" ] modelName;
      versionSuffix =
        if modelVersion != null then
          "v${toString modelVersion}"
        else if modelStage != null then
          lib.toLower modelStage
        else
          "latest";
      drvName = "mlflow-${safeName}-${versionSuffix}-raw";

      # Authentication environment variables
      authEnvVars =
        [ ]
        ++ lib.optionals (auth.tokenEnvVar or null != null) [ auth.tokenEnvVar ]
        ++ lib.optionals (auth.usernameEnvVar or null != null) [ auth.usernameEnvVar ]
        ++ lib.optionals (auth.passwordEnvVar or null != null) [ auth.passwordEnvVar ];

    in
    pkgs.stdenvNoCC.mkDerivation {
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
        python3 # For URL encoding
      ];

      # Impure environment variables for authentication
      impureEnvVars =
        lib.fetchers.proxyImpureEnvVars
        ++ [
          "MLFLOW_TRACKING_TOKEN"
          "MLFLOW_TRACKING_USERNAME"
          "MLFLOW_TRACKING_PASSWORD"
        ]
        ++ authEnvVars;

      # Environment variables for the fetcher script
      TRACKING_URI = trackingUri;
      MODEL_NAME = modelName;
      MODEL_VERSION = if modelVersion != null then toString modelVersion else "";
      MODEL_STAGE = if modelStage != null then modelStage else "";
      SOURCE_TYPE = "mlflow";

      # Network configuration
      CONNECT_TIMEOUT = connectTimeout;
      MAX_TIME = maxTime;

      # SSL certificates
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

      # Builder script
      buildPhase = ''
        runHook preBuild

        # Source common utilities
        source ${commonScript}

        # Run the MLflow fetcher
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
        inherit trackingUri modelName;
        version = modelVersion;
        stage = modelStage;
        sourceType = "mlflow";
      };

      meta = {
        description =
          "MLflow model: ${modelName}"
          + (
            if modelVersion != null then
              " v${toString modelVersion}"
            else if modelStage != null then
              " (${modelStage})"
            else
              ""
          );
      };
    };

  # Validate MLflow-specific configuration
  validateConfig =
    sourceConfig:
    let
      errors =
        [ ]
        ++ (if !(sourceConfig ? trackingUri) then [ "'trackingUri' is required" ] else [ ])
        ++ (
          if sourceConfig ? trackingUri && !(lib.isString sourceConfig.trackingUri) then
            [ "'trackingUri' must be a string" ]
          else
            [ ]
        )
        ++ (if !(sourceConfig ? modelName) then [ "'modelName' is required" ] else [ ])
        ++ (
          if sourceConfig ? modelName && !(lib.isString sourceConfig.modelName) then
            [ "'modelName' must be a string" ]
          else
            [ ]
        )
        ++ (
          if
            sourceConfig ? modelVersion
            && sourceConfig ? modelStage
            && sourceConfig.modelVersion != null
            && sourceConfig.modelStage != null
          then
            [ "specify either 'modelVersion' or 'modelStage', not both" ]
          else
            [ ]
        )
        ++ (
          if !(sourceConfig ? modelVersion) && !(sourceConfig ? modelStage) then
            [ "either 'modelVersion' or 'modelStage' is required" ]
          else
            [ ]
        );
    in
    {
      valid = errors == [ ];
      inherit errors;
    };

  # Impure environment variables this source needs
  impureEnvVars = _sourceConfig: [
    "MLFLOW_TRACKING_TOKEN"
    "MLFLOW_TRACKING_USERNAME"
    "MLFLOW_TRACKING_PASSWORD"
  ];

  # Build dependencies
  buildInputs =
    pkgs: with pkgs; [
      curl
      jq
      cacert
      coreutils
      python3
    ];

  # Extract metadata from source config
  extractMeta = sourceConfig: {
    trackingUri = sourceConfig.trackingUri;
    modelName = sourceConfig.modelName;
    version = sourceConfig.modelVersion or null;
    stage = sourceConfig.modelStage or null;
    sourceType = "mlflow";
    # For HF-style integration, use model name parts
    org = "mlflow";
    model = sourceConfig.modelName;
  };
}
