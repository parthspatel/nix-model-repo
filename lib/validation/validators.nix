# lib/validation/validators.nix
# Built-in validators for model security and integrity checking
{ lib }:

rec {
  #
  # VALIDATOR HELPERS
  #

  # Create a validator specification
  mkValidator = {
    name,
    command,
    description ? "",
    onFailure ? "abort",
    timeout ? 300,
  }: {
    inherit name command description onFailure timeout;
  };

  # Create an inline custom validator
  custom = { name, script, onFailure ? "abort", timeout ? 300 }: mkValidator {
    inherit name onFailure timeout;
    description = "Custom validator: ${name}";
    command = script;
  };

  #
  # SECURITY VALIDATORS
  #

  # Reject pickle files entirely (security risk)
  noPickleFiles = mkValidator {
    name = "no-pickle";
    description = "Ensure no pickle files are present (security risk)";
    onFailure = "abort";
    command = ''
      shopt -s nullglob globstar
      pickles=("$src"/**/*.pkl "$src"/**/*.pickle)
      if [[ ''${#pickles[@]} -gt 0 ]]; then
        echo "ERROR: Pickle files detected (potential security risk):" >&2
        printf '  %s\n' "''${pickles[@]}" >&2
        echo "" >&2
        echo "Pickle files can contain arbitrary code that executes on load." >&2
        echo "Consider using safetensors format instead." >&2
        exit 1
      fi
      echo "No pickle files found"
    '';
  };

  # Require safetensors format for weights
  safetensorsOnly = mkValidator {
    name = "safetensors-only";
    description = "Ensure model uses safetensors format (not pickle-based)";
    onFailure = "abort";
    command = ''
      shopt -s nullglob

      # Check for unsafe weight formats
      unsafe=()
      for f in "$src"/*.bin "$src"/*.pt "$src"/*.pth "$src"/**/*.bin "$src"/**/*.pt "$src"/**/*.pth; do
        [[ -f "$f" ]] && unsafe+=("$f")
      done

      if [[ ''${#unsafe[@]} -gt 0 ]]; then
        echo "ERROR: Non-safetensors weight files found:" >&2
        printf '  %s\n' "''${unsafe[@]}" >&2
        echo "" >&2
        echo "These formats may use pickle serialization." >&2
        echo "Request safetensors format from the model provider." >&2
        exit 1
      fi

      # Check that safetensors files exist
      safetensors=("$src"/*.safetensors "$src"/**/*.safetensors)
      if [[ ''${#safetensors[@]} -eq 0 ]]; then
        echo "WARNING: No safetensors files found" >&2
      else
        echo "Found ''${#safetensors[@]} safetensors files"
      fi
    '';
  };

  # Reject Python code in model directory
  noPythonCode = mkValidator {
    name = "no-python-code";
    description = "Ensure no Python code is bundled with the model";
    onFailure = "abort";
    command = ''
      shopt -s nullglob globstar
      pyfiles=("$src"/**/*.py "$src"/**/*.pyc "$src"/**/*.pyo)
      if [[ ''${#pyfiles[@]} -gt 0 ]]; then
        echo "ERROR: Python code found in model directory:" >&2
        printf '  %s\n' "''${pyfiles[@]}" >&2
        echo "" >&2
        echo "Model directories should not contain executable code." >&2
        exit 1
      fi
      echo "No Python code found"
    '';
  };

  #
  # INTEGRITY VALIDATORS
  #

  # Verify required files exist
  requiredFiles = files: mkValidator {
    name = "required-files";
    description = "Verify required files are present: ${lib.concatStringsSep ", " files}";
    onFailure = "abort";
    command = lib.concatMapStrings (f: ''
      if [[ ! -f "$src/${f}" && ! -d "$src/${f}" ]]; then
        echo "ERROR: Required file missing: ${f}" >&2
        exit 1
      fi
      echo "Found: ${f}"
    '') files;
  };

  # Enforce maximum model size
  maxSize = limit: mkValidator {
    name = "max-size-${limit}";
    description = "Ensure model size is under ${limit}";
    onFailure = "abort";
    command = ''
      limit_bytes=$(numfmt --from=iec "${limit}")
      actual_bytes=$(du -sb "$src" | cut -f1)

      if [[ $actual_bytes -gt $limit_bytes ]]; then
        actual_human=$(numfmt --to=iec "$actual_bytes")
        echo "ERROR: Model size $actual_human exceeds limit ${limit}" >&2
        exit 1
      fi

      actual_human=$(numfmt --to=iec "$actual_bytes")
      echo "Model size: $actual_human (limit: ${limit})"
    '';
  };

  # Check that config.json is valid JSON
  validConfigJson = mkValidator {
    name = "valid-config-json";
    description = "Verify config.json is valid JSON";
    onFailure = "abort";
    command = ''
      if [[ -f "$src/config.json" ]]; then
        if ! jq empty "$src/config.json" 2>/dev/null; then
          echo "ERROR: config.json is not valid JSON" >&2
          exit 1
        fi
        echo "config.json is valid"
      else
        echo "No config.json found (this may be expected)"
      fi
    '';
  };

  #
  # LICENSE VALIDATORS
  #

  # Check for license file
  licenseCheck = mkValidator {
    name = "license-check";
    description = "Check for license file presence";
    onFailure = "warn";
    command = ''
      if [[ -f "$src/LICENSE" ]] || [[ -f "$src/LICENSE.md" ]] || [[ -f "$src/LICENSE.txt" ]]; then
        echo "License file found"
        cat "$src/LICENSE"* 2>/dev/null | head -20
      else
        echo "WARNING: No license file found" >&2
        echo "Please verify the license terms for this model." >&2
      fi
    '';
  };

  #
  # SIGNATURE VALIDATORS
  #

  # Verify cryptographic signatures if present
  signatureVerify = mkValidator {
    name = "signature-verify";
    description = "Verify model signatures if present";
    onFailure = "warn";
    command = ''
      if [[ -f "$src/.signatures.json" ]]; then
        echo "Signature file found"
        # In a real implementation, this would verify signatures
        # For now, just acknowledge the file exists
        echo "Signature verification not yet implemented"
      else
        echo "No signature file found, skipping verification"
      fi
    '';
  };

  #
  # HUGGINGFACE VALIDATORS
  #

  # Verify HuggingFace cache structure
  validHfStructure = mkValidator {
    name = "valid-hf-structure";
    description = "Verify HuggingFace cache directory structure";
    onFailure = "warn";
    command = ''
      missing=()

      [[ -d "$src/blobs" ]] || missing+=("blobs/")
      [[ -d "$src/snapshots" ]] || missing+=("snapshots/")
      [[ -d "$src/refs" ]] || missing+=("refs/")

      if [[ ''${#missing[@]} -gt 0 ]]; then
        echo "WARNING: Missing HuggingFace cache directories:" >&2
        printf '  %s\n' "''${missing[@]}" >&2
        echo "This may cause issues with transformers library." >&2
      else
        echo "HuggingFace cache structure is valid"
      fi
    '';
  };
}
