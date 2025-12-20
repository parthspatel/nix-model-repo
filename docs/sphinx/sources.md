# Model Sources

Nix AI Models supports multiple model sources through a pluggable adapter system.
Each source type has its own configuration options and authentication methods.

## HuggingFace Hub

The most common source for AI models. Downloads from the HuggingFace Hub with
proper cache structure for seamless integration with the `transformers` library.

### Configuration

```nix
source.huggingface = {
  repo = "meta-llama/Llama-2-7b-hf";  # Required: org/model format
  revision = "main";                   # Optional: branch, tag, or commit SHA
  files = null;                        # Optional: list of specific files to download
};
```

### Options

**repo**
: Type: `string` | Required: Yes | Format: `"organization/model-name"`
: The HuggingFace repository identifier.

**revision**
: Type: `string` | Default: `"main"`
: Git revision to fetch. Can be a branch name, tag, or full commit SHA.
  Using a commit SHA is recommended for reproducibility.

**files**
: Type: `list of string | null` | Default: `null` (all files)
: Specific files to download. Useful for large models where you only need
  certain files (e.g., only safetensors, not pytorch_model.bin).

### Authentication

HuggingFace requires authentication for gated models (Llama, Mistral, etc.):

```nix
auth = {
  tokenEnvVar = "HF_TOKEN";  # Environment variable containing token
  # OR
  tokenFile = "/run/secrets/hf-token";  # File containing token
};
```

### Example: Public Model

```nix
fetchModel pkgs {
  name = "bert-base";
  source.huggingface.repo = "google-bert/bert-base-uncased";
  hash = "sha256-...";
}
```

### Example: Gated Model

```nix
fetchModel pkgs {
  name = "llama-2-7b";
  source.huggingface = {
    repo = "meta-llama/Llama-2-7b-hf";
    revision = "main";
  };
  hash = "sha256-...";
  auth.tokenEnvVar = "HF_TOKEN";
}
```

### Example: Specific Files Only

```nix
# Only download safetensors files (skip pytorch_model.bin)
fetchModel pkgs {
  name = "mistral-7b-safetensors";
  source.huggingface = {
    repo = "mistralai/Mistral-7B-v0.1";
    files = [
      "config.json"
      "tokenizer.json"
      "tokenizer_config.json"
      "model.safetensors.index.json"
      "model-00001-of-00002.safetensors"
      "model-00002-of-00002.safetensors"
    ];
  };
  hash = "sha256-...";
}
```

## MLFlow Registry

Fetch models from MLFlow Model Registry, commonly used in enterprise environments.

### Configuration

```nix
source.mlflow = {
  trackingUri = "https://mlflow.example.com";  # Required
  modelName = "production-model";               # Required
  version = "3";                                # Required: version number
  # OR
  stage = "Production";                         # Alternative: stage name
};
```

### Options

**trackingUri**
: Type: `string` | Required: Yes
: URL of the MLFlow tracking server.

**modelName**
: Type: `string` | Required: Yes
: Name of the registered model.

**version**
: Type: `string | int` | Required: Yes (unless `stage` is specified)
: Specific version number to fetch.

**stage**
: Type: `string` | Required: Yes (unless `version` is specified)
: Model stage to fetch (e.g., "Production", "Staging").

### Authentication

```nix
auth.tokenEnvVar = "MLFLOW_TRACKING_TOKEN";
```

### Example

```nix
fetchModel pkgs {
  name = "production-classifier";
  source.mlflow = {
    trackingUri = "https://mlflow.company.com";
    modelName = "fraud-detector";
    stage = "Production";
  };
  hash = "sha256-...";
  auth.tokenEnvVar = "MLFLOW_TRACKING_TOKEN";
}
```

## S3 Storage

Fetch models from Amazon S3 or S3-compatible storage (MinIO, etc.).

### Configuration

```nix
source.s3 = {
  bucket = "my-models-bucket";          # Required
  prefix = "models/llama-2/";           # Required: path prefix
  region = "us-west-2";                 # Optional
  endpoint = null;                      # Optional: for S3-compatible storage
};
```

### Options

**bucket**
: Type: `string` | Required: Yes
: S3 bucket name.

**prefix**
: Type: `string` | Required: Yes
: Path prefix within the bucket (like a directory path).

**region**
: Type: `string` | Default: `"us-east-1"`
: AWS region for the bucket.

**endpoint**
: Type: `string | null` | Default: `null`
: Custom endpoint URL for S3-compatible storage.

### Authentication

Uses standard AWS credential chain:

```nix
auth = {
  tokenEnvVar = "AWS_ACCESS_KEY_ID";
  # AWS_SECRET_ACCESS_KEY also required in environment
};
```

### Example: AWS S3

```nix
fetchModel pkgs {
  name = "company-model";
  source.s3 = {
    bucket = "ml-models-prod";
    prefix = "fine-tuned/gpt-neo/";
    region = "us-west-2";
  };
  hash = "sha256-...";
}
```

### Example: MinIO

```nix
fetchModel pkgs {
  name = "local-model";
  source.s3 = {
    bucket = "models";
    prefix = "bert/";
    endpoint = "http://minio.local:9000";
  };
  hash = "sha256-...";
}
```

## Git LFS

Fetch models from any Git repository using Git LFS for large files.

### Configuration

```nix
source.git-lfs = {
  url = "https://github.com/org/model-repo.git";  # Required
  rev = "v1.0.0";                                  # Required: tag, branch, or SHA
  subdir = null;                                   # Optional: subdirectory
};
```

### Options

**url**
: Type: `string` | Required: Yes
: Git repository URL.

**rev**
: Type: `string` | Required: Yes
: Git revision (tag, branch, or commit SHA).

**subdir**
: Type: `string | null` | Default: `null`
: Subdirectory within the repository containing the model.

### Example

```nix
fetchModel pkgs {
  name = "custom-model";
  source.git-lfs = {
    url = "https://github.com/company/ml-models.git";
    rev = "v2.1.0";
    subdir = "models/classifier";
  };
  hash = "sha256-...";
}
```

## Git-Xet

Fetch models using Git-Xet for efficient large file handling with deduplication.

### Configuration

```nix
source.git-xet = {
  url = "xet://xethub.com/org/model";  # Required
  rev = "main";                         # Required
};
```

### Example

```nix
fetchModel pkgs {
  name = "xet-model";
  source.git-xet = {
    url = "xet://xethub.com/company/large-model";
    rev = "main";
  };
  hash = "sha256-...";
}
```

## HTTP/HTTPS URL

Direct download from any HTTP/HTTPS URL.

### Configuration

```nix
source.url = {
  url = "https://example.com/model.tar.gz";  # Required
  extract = true;                             # Optional: auto-extract archives
};
```

### Example

```nix
fetchModel pkgs {
  name = "downloaded-model";
  source.url = {
    url = "https://releases.company.com/models/v1.0/model.tar.gz";
    extract = true;
  };
  hash = "sha256-...";
}
```

## Ollama

Fetch models from the Ollama registry.

### Configuration

```nix
source.ollama = {
  model = "llama2";     # Required: model name
  tag = "latest";       # Optional: model tag
};
```

### Example

```nix
fetchModel pkgs {
  name = "ollama-llama2";
  source.ollama = {
    model = "llama2";
    tag = "7b";
  };
  hash = "sha256-...";
}
```

## Mock Source (Testing)

A mock source for testing that creates empty model structures without network access.

### Configuration

```nix
source.mock = {
  org = "test-org";                      # Optional
  model = "test-model";                  # Optional
  files = [ "config.json" ];             # Optional: files to create
  commitSha = "abc123...";               # Optional: fake commit SHA
};
```

### Example

```nix
fetchModel pkgs {
  name = "test-model";
  source.mock = {
    org = "test";
    model = "empty";
    files = [ "config.json" "tokenizer.json" ];
  };
  hash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=";
}
```

## Source Factories

For DRY configuration, use source factories to create reusable source templates:

```nix
let
  sources = nix-ai-models.lib.sources;

  # Create a factory for your organization's models
  companyHF = sources.mkHuggingFace {
    defaultAuth.tokenEnvVar = "HF_TOKEN";
  };

  companyS3 = sources.mkS3 {
    bucket = "company-models";
    region = "us-west-2";
  };
in {
  llama = fetchModel pkgs {
    name = "llama-2";
    source = companyHF "meta-llama/Llama-2-7b-hf";
    hash = "sha256-...";
  };

  internal = fetchModel pkgs {
    name = "internal-model";
    source = companyS3 "models/internal-v1/";
    hash = "sha256-...";
  };
}
```

See [Configuration](configuration.md) for more details on source factories.
