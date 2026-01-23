# lib/integration.nix
# Integration utilities for HuggingFace cache and environment setup
{ lib, pkgs }:

{
  # Create a shell hook that sets up HuggingFace cache symlinks
  # Usage in a devShell:
  #   shellHook = mkShellHook { models = [ { drv = myModel; org = "meta-llama"; model = "Llama-2-7b-hf"; } ]; };
  mkShellHook =
    {
      models,
      cacheDir ? null,
    }:
    let
      hfDir = if cacheDir != null then cacheDir else "$HOME/.cache/huggingface/hub";

      setupModel =
        {
          drv,
          org,
          model,
          ...
        }:
        ''
          # Setup HuggingFace cache for ${org}/${model}
          _hf_link_path="${hfDir}/models--${org}--${model}"
          _hf_model_path="${drv}"

          if [[ -L "$_hf_link_path" ]]; then
            # Remove existing symlink
            rm "$_hf_link_path"
          elif [[ -e "$_hf_link_path" ]]; then
            echo "WARNING: $_hf_link_path exists and is not a symlink, skipping" >&2
          fi

          if [[ ! -e "$_hf_link_path" ]]; then
            mkdir -p "$(dirname "$_hf_link_path")"
            ln -s "$_hf_model_path" "$_hf_link_path"
            echo "Linked: ${org}/${model} → $_hf_model_path"
          fi
        '';

    in
    ''
      # Setup HuggingFace cache directory
      mkdir -p "${hfDir}"

      ${lib.concatMapStrings setupModel models}

      # Set environment for offline mode
      export HF_HUB_OFFLINE=1
      export TRANSFORMERS_OFFLINE=1

      echo ""
      echo "HuggingFace models ready (offline mode enabled):"
      ${lib.concatMapStrings (
        { org, model, ... }:
        ''
          echo "  - ${org}/${model}"
        ''
      ) models}
    '';

  # Create symlinks for a model in the HuggingFace cache
  # Returns a script that can be run to set up symlinks
  mkHfSymlinks =
    {
      modelPath, # Path to model in Nix store
      org, # Organization name
      model, # Model name
      cacheDir ? null,
    }:
    let
      hfDir = if cacheDir != null then cacheDir else "$HOME/.cache/huggingface/hub";
      linkName = "models--${org}--${model}";
    in
    pkgs.writeShellScript "setup-hf-symlinks-${org}-${model}" ''
      set -euo pipefail

      cache_dir="${hfDir}"
      mkdir -p "$cache_dir"

      link_path="$cache_dir/${linkName}"

      # Remove existing symlink if present
      if [[ -L "$link_path" ]]; then
        rm "$link_path"
      elif [[ -e "$link_path" ]]; then
        echo "WARNING: $link_path exists and is not a symlink, skipping" >&2
        exit 0
      fi

      # Create symlink
      ln -s "${modelPath}" "$link_path"
      echo "Created symlink: $link_path → ${modelPath}"
    '';

  # Create a wrapper script that sets up model environment variables
  mkModelWrapper =
    {
      program, # The program to wrap
      models, # List of { path, envVar }
      name ? null,
    }:
    let
      wrapperName = if name != null then name else baseNameOf program;
    in
    pkgs.writeShellScriptBin wrapperName ''
      ${lib.concatMapStrings (
        { path, envVar, ... }:
        ''
          export ${envVar}="${path}"
        ''
      ) models}

      exec ${program} "$@"
    '';

  # Extract org and model from a HuggingFace repo string
  parseHfRepo =
    repo:
    let
      parts = lib.splitString "/" repo;
    in
    {
      org = lib.elemAt parts 0;
      model = lib.elemAt parts 1;
    };

  # Generate the HuggingFace cache path for a model
  mkHfCachePath =
    {
      org,
      model,
      cacheDir ? "$HOME/.cache/huggingface/hub",
    }:
    "${cacheDir}/models--${org}--${model}";
}
