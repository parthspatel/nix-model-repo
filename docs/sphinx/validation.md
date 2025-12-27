# Validation Framework

Nix Model Repo includes a comprehensive validation framework for security scanning
and model verification. Validation runs in a separate derivation after the model
is fetched, ensuring reproducibility while enabling security checks.

## How Validation Works

Validation uses a **two-phase architecture**:

1. **Phase 1 (FOD)**: Model is fetched as a Fixed Output Derivation with hash verification
2. **Phase 2 (Validation)**: A separate derivation runs validators against the fetched model

This design ensures:

- Hash verification happens first (reproducibility)
- Validators can use any tools without affecting FOD purity
- Validation results are cached
- Failed validation doesn't corrupt the cache

## Basic Usage

```nix
fetchModel pkgs {
  name = "my-model";
  source.huggingface.repo = "org/model";
  hash = "sha256-...";

  validation = {
    enable = true;           # Default: true
    skipDefaults = false;    # Use built-in validators
    onFailure = "abort";     # Fail build on validation error
  };
}
```

## Validation Presets

Instead of configuring individual options, use presets for common scenarios:

### strict

Maximum security - fails on any security concern.

```nix
let
  presets = nix-model-repo.lib.validation.presets;
in
  fetchModel pkgs {
    name = "secure-model";
    source.huggingface.repo = "org/model";
    hash = "sha256-...";
    validation = presets.strict;
  }
```

**Includes:**
- ModelScan security scanning
- No pickle files allowed
- Safetensors only (no PyTorch .bin files)
- File type verification
- Size limits

### standard

Balanced security with reasonable defaults.

```nix
validation = presets.standard;
```

**Includes:**
- ModelScan scanning
- Pickle file scanning (warns but allows)
- Basic file verification

### minimal

Fast validation with warnings only.

```nix
validation = presets.minimal;
```

**Includes:**
- Basic file presence checks
- Warnings instead of errors

### none

Disable all validation.

```nix
validation = presets.none;
# Equivalent to: validation.enable = false;
```

### paranoid

Maximum security plus additional checks.

```nix
validation = presets.paranoid;
```

**Includes:**
- Everything from `strict`
- Content analysis
- Metadata verification
- Extended timeout for thorough scanning

## Built-in Validators

### noPickleFiles

Rejects models containing Python pickle files (`.pkl`, `.pickle`, `pickle` in name).
Pickle files can contain arbitrary code and are a security risk.

```nix
validation.validators = [
  validators.noPickleFiles
];
```

### safetensorsOnly

Requires all model weights to be in safetensors format.
Rejects `.bin`, `.pt`, `.pth` files.

```nix
validation.validators = [
  validators.safetensorsOnly
];
```

### maxSize

Limits total model size.

```nix
validation.validators = [
  (validators.maxSize "10G")   # 10 gigabytes
  (validators.maxSize "500M")  # 500 megabytes
];
```

### requiredFiles

Ensures specific files exist in the model.

```nix
validation.validators = [
  (validators.requiredFiles [ "config.json" "tokenizer.json" ])
];
```

### noSymlinks

Rejects models containing symbolic links (security measure).

```nix
validation.validators = [
  validators.noSymlinks
];
```

### fileTypes

Whitelist allowed file extensions.

```nix
validation.validators = [
  (validators.fileTypes [ ".json" ".safetensors" ".txt" ".md" ])
];
```

### modelscan

Runs the ModelScan security scanner.

```nix
validation.validators = [
  validators.modelscan
];
```

## Custom Validators

Create custom validators for your specific needs:

```nix
let
  mkValidator = nix-model-repo.lib.validation.mkValidator;

  # Custom validator that checks for a license file
  requireLicense = mkValidator {
    name = "require-license";
    description = "Ensure model has a license file";
    command = ''
      if [ ! -f "$src/LICENSE" ] && [ ! -f "$src/LICENSE.md" ]; then
        echo "ERROR: No license file found"
        exit 1
      fi
      echo "License file found"
    '';
  };

  # Custom validator with parameters
  maxFiles = count: mkValidator {
    name = "max-files-${toString count}";
    description = "Limit number of files to ${toString count}";
    command = ''
      file_count=$(find "$src" -type f | wc -l)
      if [ "$file_count" -gt ${toString count} ]; then
        echo "ERROR: Too many files: $file_count > ${toString count}"
        exit 1
      fi
      echo "File count OK: $file_count"
    '';
  };
in
  fetchModel pkgs {
    name = "validated-model";
    source.huggingface.repo = "org/model";
    hash = "sha256-...";
    validation.validators = [
      requireLicense
      (maxFiles 100)
    ];
  }
```

### Validator Interface

Custom validators must conform to this interface:

```nix
{
  name = "validator-name";           # Unique identifier
  description = "What it checks";    # Human-readable description
  command = "shell script";          # Script to run
  # Optional:
  timeout = 300;                     # Timeout in seconds
  onFailure = "abort";               # "abort" | "warn" | "skip"
  buildInputs = [ pkgs.jq ];         # Additional dependencies
}
```

The `command` script has access to:

- `$src` - Path to the fetched model
- `$out` - Output path for validation artifacts
- Standard coreutils and common tools

## Failure Handling

Control what happens when validation fails:

### abort (default)

Fail the build immediately.

```nix
validation.onFailure = "abort";
```

### warn

Log a warning but continue the build.

```nix
validation.onFailure = "warn";
```

### skip

Silently continue (useful for optional validators).

```nix
validation.onFailure = "skip";
```

### Per-Validator Failure Handling

Override failure behavior for individual validators:

```nix
validation.validators = [
  validators.noPickleFiles                    # Uses global onFailure
  (validators.maxSize "50G" // { onFailure = "warn"; })  # Always warn
];
```

## Validation Timeout

Set timeout for validation (useful for large models):

```nix
validation = {
  enable = true;
  timeout = 600;  # 10 minutes per validator
};
```

## Example Configurations

### High-Security Production

```nix
fetchModel pkgs {
  name = "production-model";
  source.huggingface.repo = "company/model";
  hash = "sha256-...";

  validation = {
    enable = true;
    validators = [
      validators.noPickleFiles
      validators.safetensorsOnly
      validators.modelscan
      (validators.maxSize "20G")
      (validators.requiredFiles [ "config.json" ])
      validators.noSymlinks
    ];
    onFailure = "abort";
    timeout = 900;  # 15 minutes for thorough scanning
  };
}
```

### Development/Testing

```nix
fetchModel pkgs {
  name = "dev-model";
  source.huggingface.repo = "org/experimental";
  hash = "sha256-...";

  validation = {
    enable = true;
    skipDefaults = true;  # Skip slow scans
    validators = [
      (validators.requiredFiles [ "config.json" ])
    ];
    onFailure = "warn";   # Don't fail on issues
  };
}
```

### Combining Presets with Custom Validators

```nix
let
  presets = nix-model-repo.lib.validation.presets;
  validators = nix-model-repo.lib.validation.validators;
in
  fetchModel pkgs {
    name = "custom-validated";
    source.huggingface.repo = "org/model";
    hash = "sha256-...";

    validation = presets.standard // {
      validators = presets.standard.validators ++ [
        (validators.maxSize "10G")
        myCustomValidator
      ];
    };
  }
```

## Debugging Validation

To debug validation failures:

1. Build with `--keep-failed` to inspect the build directory
2. Check the validation log in the derivation output
3. Run validators manually on the raw model:

```bash
# Get the raw (unvalidated) model
nix build .#my-model.passthru.raw

# Inspect it
ls -la result/
```

## Disabling Validation

For trusted sources or when validation is handled externally:

```nix
fetchModel pkgs {
  name = "trusted-model";
  source.huggingface.repo = "org/model";
  hash = "sha256-...";
  validation.enable = false;
}
```

```{warning}
Disabling validation removes important security checks. Only do this for
models you completely trust or when validation is handled by other means.
```

## Complete Examples

For full configurations demonstrating validation patterns, see:

- [Validation Presets Flake](examples.md#validation-presets-flake) - All presets and custom validators
- [Production Inference](examples.md#production-inference-flake) - Strict security for production
- [Devenv with Validation](examples.md#ml-development-with-devenv) - Validation in devenv environments
