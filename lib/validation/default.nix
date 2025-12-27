# lib/validation/default.nix
# Validation framework for model security and integrity checking
{ lib, pkgs }:

let
  validators = import ./validators.nix { inherit lib; };
  presets = import ./presets.nix { inherit lib; };

  # Default validation settings
  defaultValidation = {
    enable = true;
    skipDefaults = false;
    defaults = {
      modelscan = true;
      pickleScan = true;
      checksums = true;
    };
    validators = [];
    onFailure = "abort";
    timeout = 300;
  };

  # Merge validation config with defaults
  normalizeValidation = validation:
    let
      merged = defaultValidation // validation;
    in merged // {
      defaults = defaultValidation.defaults // (validation.defaults or {});
    };

in {
  # Re-export validators and presets
  inherit validators presets;

  # Create a validator specification (re-export from validators)
  inherit (validators) mkValidator custom;

  # Build a validation derivation that runs validators on a model
  mkValidationDerivation = {
    name,
    src,  # The FOD output (raw model)
    validation ? {},
  }:
    let
      config = normalizeValidation validation;

      # Skip validation entirely if disabled
      isEnabled = config.enable;

      # Combine all validators
      allValidators =
        # Custom validators from config
        config.validators
        # TODO: Add default validators (modelscan, etc.) when skipDefaults is false
        # For now, just use custom validators
        ;

      # Generate validation script
      validatorScript = v: ''
        echo ""
        echo "=== Validator: ${v.name} ==="
        echo "${v.description}"
        echo ""

        set +e
        timeout ${toString v.timeout} bash -c ${lib.escapeShellArg v.command}
        validator_exit_code=$?
        set -e

        if [[ $validator_exit_code -eq 124 ]]; then
          echo "TIMEOUT: Validator ${v.name} exceeded ${toString v.timeout}s limit" >&2
          ${if v.onFailure == "abort" then ''
            exit 1
          '' else if v.onFailure == "warn" then ''
            echo "WARNING: Continuing despite timeout" >&2
          '' else ''
            true
          ''}
        elif [[ $validator_exit_code -ne 0 ]]; then
          echo "FAILED: Validator ${v.name} exited with code $validator_exit_code" >&2
          ${if v.onFailure == "abort" then ''
            exit 1
          '' else if v.onFailure == "warn" then ''
            echo "WARNING: Continuing despite validation failure" >&2
          '' else ''
            true
          ''}
        else
          echo "PASSED: ${v.name}"
        fi
      '';

      validationScript = ''
        set -euo pipefail

        echo "========================================"
        echo "Model Validation"
        echo "========================================"
        echo ""
        echo "Source: $src"
        echo "Validators: ${toString (builtins.length allValidators)}"
        echo ""

        ${if allValidators == [] then ''
          echo "No validators configured, skipping validation"
        '' else lib.concatMapStrings validatorScript allValidators}

        echo ""
        echo "========================================"
        echo "Validation Complete"
        echo "========================================"
      '';

    in
      if !isEnabled then
        # Validation disabled - just copy the source
        pkgs.runCommand name {
          inherit src;
        } ''
          cp -r $src $out
          chmod -R u+w $out

          # Update metadata to indicate validation was skipped
          if [[ -f $out/.nix-model-repo-meta.json ]]; then
            ${pkgs.jq}/bin/jq '. + {"validation": {"enabled": false, "skipped": true}}' \
              $out/.nix-model-repo-meta.json > $out/.nix-model-repo-meta.json.tmp
            mv $out/.nix-model-repo-meta.json.tmp $out/.nix-model-repo-meta.json
          fi
        ''
      else
        # Validation enabled - run validators
        pkgs.stdenvNoCC.mkDerivation {
          inherit name src;

          nativeBuildInputs = with pkgs; [
            jq
            coreutils
            findutils
          ];

          dontUnpack = true;

          buildPhase = ''
            runHook preBuild

            ${validationScript}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            # Copy validated model to output
            cp -r $src $out
            chmod -R u+w $out

            # Update metadata with validation results
            if [[ -f $out/.nix-model-repo-meta.json ]]; then
              ${pkgs.jq}/bin/jq '. + {
                "validation": {
                  "enabled": true,
                  "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
                  "validators": ${builtins.toJSON (map (v: v.name) allValidators)},
                  "passed": true
                }
              }' $out/.nix-model-repo-meta.json > $out/.nix-model-repo-meta.json.tmp
              mv $out/.nix-model-repo-meta.json.tmp $out/.nix-model-repo-meta.json
            fi

            runHook postInstall
          '';
        };

  # Merge validators from preset with custom validators
  mergeValidators = preset: customValidators:
    let
      presetValidators = preset.validators or [];
    in
      presetValidators ++ customValidators;
}
