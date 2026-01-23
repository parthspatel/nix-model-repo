# lib/default.nix
# Main library exports for nix-model-repo
{ lib, pkgs }:

let
  # Import all modules
  types = import ./types.nix { inherit lib; };
  sources = import ./sources { inherit lib pkgs; };
  validation = import ./validation { inherit lib pkgs; };
  integration = import ./integration.nix { inherit lib pkgs; };

  # Create the main fetchModel function
  fetchModel = import ./fetchModel.nix {
    inherit
      lib
      pkgs
      types
      sources
      validation
      integration
      ;
  };

in
{
  # Main API
  inherit fetchModel;

  # Source factories for creating source configurations
  # Usage: sources.huggingface.metaLlama "Llama-2-7b-hf"
  sources = sources.factories;

  # Source adapter access (advanced)
  sourceAdapters = sources.adapters;

  # Validation presets and validators
  validation = {
    inherit (validation) presets validators mkValidator;
  };

  # Integration helpers
  inherit (integration)
    mkShellHook
    mkHfSymlinks
    mkModelWrapper
    parseHfRepo
    mkHfCachePath
    ;

  # Type utilities (advanced)
  types = {
    inherit (types) validateConfig validateSource normalizeHash;
    inherit (types) knownSourceTypes defaultValidation defaultNetwork;
  };

  # Instantiate model definitions with this pkgs
  # Usage: instantiate modelDefs
  # This recursively walks the definition tree and applies fetchModel
  # to any attrset that looks like a model config (has name, source, hash)
  instantiate =
    let
      isModelConfig = x: builtins.isAttrs x && x ? name && x ? source && x ? hash;
      instantiateRecursive =
        defs:
        lib.mapAttrs (
          _name: value:
          if isModelConfig value then
            fetchModel value
          else if builtins.isAttrs value then
            instantiateRecursive value
          else
            value
        ) defs;
    in
    instantiateRecursive;
}
