# lib/fetchModel.nix
# Core function that orchestrates model fetching, validation, and integration
{ lib, pkgs, types, sources, validation, integration }:

# Main fetchModel function
# Usage: fetchModel { name, source, hash, validation?, integration?, network?, auth?, meta? }
config:

let
  # Validate the configuration
  configValidation = types.validateConfig config;

  # Merge with defaults
  mergedConfig = types.mergeWithDefaults config;

  # Get the source adapter
  sourceAdapter = sources.dispatch mergedConfig.source;
  sourceType = configValidation.sourceType;
  sourceConfig = mergedConfig.source.${sourceType};

  # Extract metadata from source
  sourceMeta = sourceAdapter.extractMeta sourceConfig;

  #
  # PHASE 1: FOD Fetch (raw model download)
  #
  rawModel = sourceAdapter.mkFetchDerivation {
    name = "${mergedConfig.name}-raw";
    hash = mergedConfig.hash;
    inherit sourceConfig;
    auth = mergedConfig.auth;
    network = mergedConfig.network;
  };

  #
  # PHASE 2: Validation
  #
  validatedModel = validation.mkValidationDerivation {
    name = mergedConfig.name;
    src = rawModel;
    validation = mergedConfig.validation;
  };

  #
  # PHASE 3: Integration setup
  #
  # Add passthru attributes for integration helpers
  finalModel = validatedModel.overrideAttrs (old: {
    passthru = (old.passthru or {}) // {
      # Raw FOD output (before validation)
      raw = rawModel;

      # Source metadata
      meta = sourceMeta;

      # Source type
      inherit sourceType;

      # Original config
      config = mergedConfig;

      # Integration helpers
      shellHook = integration.mkShellHook {
        models = [{
          drv = validatedModel;
          inherit (sourceMeta) org model;
        }];
      };

      setupSymlinks = integration.mkHfSymlinks {
        modelPath = validatedModel;
        inherit (sourceMeta) org model;
      };
    };

    # Standard Nix meta attributes
    meta = (old.meta or {}) // mergedConfig.meta // {
      description = old.meta.description or "AI model: ${sourceMeta.org}/${sourceMeta.model}";
    };
  });

in
  # Fail fast if config is invalid
  if !configValidation.valid then
    throw "Invalid fetchModel configuration:\n  ${lib.concatStringsSep "\n  " configValidation.errors}"
  else
    finalModel
