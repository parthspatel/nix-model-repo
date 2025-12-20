# lib/default.nix
# Main library exports for nix-ai-models
{ lib, pkgs }:

let
  # Import all modules
  types = import ./types.nix { inherit lib; };
  sources = import ./sources { inherit lib pkgs; };
  validation = import ./validation { inherit lib pkgs; };
  integration = import ./integration.nix { inherit lib pkgs; };

  # Create the main fetchModel function
  fetchModel = import ./fetchModel.nix {
    inherit lib pkgs types sources validation integration;
  };

in {
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
  inherit (integration) mkShellHook mkHfSymlinks mkModelWrapper parseHfRepo mkHfCachePath;

  # Type utilities (advanced)
  types = {
    inherit (types) validateConfig validateSource normalizeHash;
    inherit (types) knownSourceTypes defaultValidation defaultNetwork;
  };

  # Instantiate model definitions with this pkgs
  # Usage: instantiate modelDefs
  instantiate = defs:
    lib.mapAttrsRecursive
      (_path: def: fetchModel def)
      defs;
}
