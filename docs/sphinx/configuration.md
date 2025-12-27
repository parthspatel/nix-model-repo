# Configuration Reference

This page documents all configuration options for `fetchModel`.

## Full Configuration Example

```nix
fetchModel pkgs {
  # Required
  name = "my-model";
  source.huggingface.repo = "org/model";
  hash = "sha256-...";

  # Optional: Validation
  validation = {
    enable = true;
    skipDefaults = false;
    validators = [];
    onFailure = "abort";
    timeout = 300;
  };

  # Optional: Integration
  integration = {
    huggingface = {
      enable = true;
      org = null;    # Override org name
      model = null;  # Override model name
    };
  };

  # Optional: Network
  network = {
    timeout = {
      connect = 30;
      read = 300;
    };
    retry = {
      maxAttempts = 3;
      baseDelay = 2;
    };
    bandwidth.limit = null;  # e.g., "10M"
    proxy = null;
  };

  # Optional: Authentication
  auth = {
    tokenEnvVar = null;  # e.g., "HF_TOKEN"
    tokenFile = null;    # e.g., "/run/secrets/hf-token"
  };

  # Optional: Nix meta
  meta = {
    description = "My model";
    license = lib.licenses.mit;
  };
}
```

## Required Options

### name

- **Type:** `string`
- **Required:** Yes

The name for the derivation. This becomes part of the Nix store path.

```nix
name = "llama-2-7b";
```

### source

- **Type:** `attrset`
- **Required:** Yes

The model source configuration. Must specify exactly one source type.
See [Sources](sources.md) for all available source types.

```nix
# HuggingFace
source.huggingface.repo = "meta-llama/Llama-2-7b-hf";

# S3
source.s3 = {
  bucket = "my-bucket";
  prefix = "models/llama";
  region = "us-west-2";
};
```

### hash

- **Type:** `string` (SRI format)
- **Required:** Yes

The expected SHA256 hash of the model in SRI format.

```nix
hash = "sha256-abc123...";
```

To obtain the hash, use a placeholder and build once - Nix will report the correct hash.

## Validation Options

### validation.enable

- **Type:** `bool`
- **Default:** `true`

Enable or disable validation entirely.

```nix
validation.enable = false;  # Skip all validation
```

### validation.skipDefaults

- **Type:** `bool`
- **Default:** `false`

Skip the built-in default validators (modelscan, pickle scan).

```nix
validation.skipDefaults = true;
```

### validation.validators

- **Type:** `list of validator`
- **Default:** `[]`

Additional validators to run. See [Validation](validation.md) for available validators.

```nix
validation.validators = [
  validators.noPickleFiles
  validators.safetensorsOnly
  (validators.maxSize "50G")
];
```

### validation.onFailure

- **Type:** `"abort" | "warn" | "skip"`
- **Default:** `"abort"`

Global failure handling for validators:

- `"abort"`: Fail the build if any validator fails
- `"warn"`: Log a warning but continue
- `"skip"`: Silently continue

```nix
validation.onFailure = "warn";
```

### validation.timeout

- **Type:** `int` (seconds)
- **Default:** `300`

Timeout for each validator in seconds.

```nix
validation.timeout = 600;  # 10 minutes
```

## Network Options

### network.timeout.connect

- **Type:** `int` (seconds)
- **Default:** `30`

Connection timeout for downloads.

### network.timeout.read

- **Type:** `int` (seconds)
- **Default:** `300`

Read timeout for downloads. Set to `0` for no limit.

### network.retry.maxAttempts

- **Type:** `int`
- **Default:** `3`

Maximum number of retry attempts for failed downloads.

### network.retry.baseDelay

- **Type:** `int` (seconds)
- **Default:** `2`

Base delay between retries (exponential backoff).

### network.bandwidth.limit

- **Type:** `string | null`
- **Default:** `null`

Bandwidth limit for downloads (e.g., `"10M"` for 10 MB/s).

```nix
network.bandwidth.limit = "50M";
```

### network.proxy

- **Type:** `string | null`
- **Default:** `null`

HTTP proxy URL for downloads.

```nix
network.proxy = "http://proxy.example.com:8080";
```

## Authentication Options

### auth.tokenEnvVar

- **Type:** `string | null`
- **Default:** `null`

Environment variable name containing the authentication token.

```nix
auth.tokenEnvVar = "HF_TOKEN";
```

### auth.tokenFile

- **Type:** `path | null`
- **Default:** `null`

Path to a file containing the authentication token.

```nix
auth.tokenFile = "/run/secrets/hf-token";
```

## Integration Options

### integration.huggingface.enable

- **Type:** `bool`
- **Default:** `true`

Create HuggingFace-compatible cache structure.

### integration.huggingface.org

- **Type:** `string | null`
- **Default:** `null` (derived from source)

Override the organization name for cache structure.

### integration.huggingface.model

- **Type:** `string | null`
- **Default:** `null` (derived from source)

Override the model name for cache structure.

## Using Presets

Instead of configuring individual options, use validation presets:

```nix
let
  presets = nix-model-repo.lib.validation.presets;
in
  fetchModel pkgs {
    name = "my-model";
    source.huggingface.repo = "org/model";
    hash = "sha256-...";
    validation = presets.strict;  # or: standard, minimal, none, paranoid
  };
```

See [Validation](validation.md) for preset details.

## Complete Examples

For full, working configurations, see:

- [Basic Model Flake](examples.md#basic-model-flake) - Minimal setup
- [Multi-Model Flake](examples.md#multi-model-flake) - Multiple models
- [Production Inference](examples.md#production-inference-flake) - All options with strict validation
- [Validation Presets](examples.md#validation-presets-flake) - Different validation configurations
- [Devenv Configuration](examples.md#devenv-configuration) - Using with devenv.sh
