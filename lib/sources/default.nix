# lib/sources/default.nix
# Source adapter framework and dispatch
{ lib, pkgs }:

let
  # Import individual source adapters
  adapters = {
    huggingface = import ./huggingface.nix { inherit lib pkgs; };
    mock = import ./mock.nix { inherit lib pkgs; };
    # Additional adapters will be added here:
    # mlflow = import ./mlflow.nix { inherit lib pkgs; };
    # s3 = import ./s3.nix { inherit lib pkgs; };
    # git-lfs = import ./git-lfs.nix { inherit lib pkgs; };
    # git-xet = import ./git-xet.nix { inherit lib pkgs; };
    # url = import ./url.nix { inherit lib pkgs; };
    # ollama = import ./ollama.nix { inherit lib pkgs; };
  };

  # Import source factories
  factories = import ./factories.nix { inherit lib; };

in {
  # All available adapters
  inherit adapters;

  # Source factories for users
  inherit factories;

  # Get adapter for a source type
  # Returns: adapter or throws error
  getAdapter = sourceType:
    if adapters ? ${sourceType} then
      adapters.${sourceType}
    else
      throw "Unknown source type: ${sourceType}. Available: ${lib.concatStringsSep ", " (lib.attrNames adapters)}";

  # Dispatch: given source config, return the right adapter
  # The source config should have exactly one key matching a known source type
  dispatch = sourceConfig:
    let
      types = import ../types.nix { inherit lib; };
      validation = types.validateSource sourceConfig;
    in
      if !validation.valid then
        throw "Invalid source configuration: ${lib.concatStringsSep "; " validation.errors}"
      else
        adapters.${validation.sourceType};

  # Build FOD derivation for a source
  # This is the main entry point for fetching
  mkFetchDerivation = {
    name,
    source,
    hash,
    auth ? {},
    network ? {},
  }:
    let
      types = import ../types.nix { inherit lib; };
      validation = types.validateSource source;
      adapter = adapters.${validation.sourceType};
      sourceConfig = source.${validation.sourceType};
    in
      if !validation.valid then
        throw "Invalid source configuration: ${lib.concatStringsSep "; " validation.errors}"
      else
        adapter.mkFetchDerivation {
          inherit name hash sourceConfig auth network;
        };
}
