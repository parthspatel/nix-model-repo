# Model Sources

Nix Model Repo supports multiple model sources through a pluggable adapter system.
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

## MLflow Model Registry

Fetch models from MLflow Model Registry, commonly used in enterprise environments
for model versioning, staging, and deployment workflows.

### Configuration

```nix
source.mlflow = {
  trackingUri = "https://mlflow.example.com";  # Required: MLflow server URL
  modelName = "production-model";               # Required: registered model name
  modelVersion = 3;                             # Option 1: specific version number
  # OR
  modelStage = "Production";                    # Option 2: stage name
};
```

### Options

**trackingUri**
: Type: `string` | Required: Yes
: URL of the MLflow tracking server. Can be:

- `https://mlflow.example.com` - Remote server
- `http://localhost:5000` - Local development server
- `databricks://` - Databricks-hosted MLflow

**modelName**
: Type: `string` | Required: Yes
: Name of the registered model in the Model Registry.

**modelVersion**
: Type: `int | null` | Required: Yes (unless `modelStage` is specified)
: Specific version number to fetch. Recommended for reproducibility.

**modelStage**
: Type: `string | null` | Required: Yes (unless `modelVersion` is specified)
: Model stage to fetch. Common stages:

- `"Production"` - Production-ready models
- `"Staging"` - Models being validated
- `"Archived"` - Deprecated models
- `"None"` - Unassigned models

### Authentication

MLflow supports multiple authentication methods:

**Bearer Token (recommended for remote servers)**

```nix
auth.tokenEnvVar = "MLFLOW_TRACKING_TOKEN";
```

Set the environment variable before building:

```bash
export MLFLOW_TRACKING_TOKEN="your-token-here"
```

**Basic Authentication**

```bash
export MLFLOW_TRACKING_USERNAME="user"
export MLFLOW_TRACKING_PASSWORD="password"
```

**Databricks**

```bash
export DATABRICKS_HOST="https://your-workspace.cloud.databricks.com"
export DATABRICKS_TOKEN="your-databricks-token"
```

### Example: Fetch by Version

```nix
fetchModel pkgs {
  name = "fraud-detector-v3";
  source.mlflow = {
    trackingUri = "https://mlflow.company.com";
    modelName = "fraud-detector";
    modelVersion = 3;
  };
  hash = "sha256-...";
  auth.tokenEnvVar = "MLFLOW_TRACKING_TOKEN";
}
```

### Example: Fetch Production Stage

```nix
fetchModel pkgs {
  name = "production-classifier";
  source.mlflow = {
    trackingUri = "https://mlflow.company.com";
    modelName = "fraud-detector";
    modelStage = "Production";
  };
  hash = "sha256-...";
  auth.tokenEnvVar = "MLFLOW_TRACKING_TOKEN";
}
```

### Example: Local MLflow Server

```nix
fetchModel pkgs {
  name = "local-model";
  source.mlflow = {
    trackingUri = "http://localhost:5000";
    modelName = "my-experiment-model";
    modelVersion = 1;
  };
  hash = "sha256-...";
  # No auth needed for local server
}
```

### Example: Using Source Factory

Create a reusable factory for your MLflow server:

```nix
let
  sources = nix-model-repo.lib.sources;

  # Create factory for company MLflow
  companyMlflow = sources.mkMlflow {
    trackingUri = "https://mlflow.company.com";
  };
in {
  # Fetch production model
  fraud-detector = fetchModel pkgs {
    name = "fraud-detector";
    source = companyMlflow {
      modelName = "fraud-detector";
      stage = "Production";
    };
    hash = "sha256-...";
    auth.tokenEnvVar = "MLFLOW_TRACKING_TOKEN";
  };

  # Fetch specific version
  classifier-v5 = fetchModel pkgs {
    name = "classifier-v5";
    source = companyMlflow {
      modelName = "document-classifier";
      version = 5;
    };
    hash = "sha256-...";
    auth.tokenEnvVar = "MLFLOW_TRACKING_TOKEN";
  };
}
```

### Output Structure

The fetched model includes:

- All model artifacts from the MLflow run
- `MLmodel` file (if present) with model metadata
- `.nix-model-repo-meta.json` with fetch metadata

### Troubleshooting

**401 Unauthorized**
: Set authentication credentials via environment variables

**404 Not Found**
: Check that the model name and version/stage exist in the registry

**No version found for stage**
: Ensure a model version is assigned to the specified stage

**SSL Certificate errors**
: The fetcher uses system CA certificates. For self-signed certs, you may need to add them to your system trust store

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
  sources = nix-model-repo.lib.sources;

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

## Complete Examples

For working multi-source configurations, see the [Multi-Source Example](examples.md#multi-source-flake) which demonstrates:

- Fetching from HuggingFace Hub
- Using company S3 buckets
- Pulling from MLFlow registry
- Cloning Git LFS repositories

Also see [Devenv Examples](examples.md#devenv-configuration) for using sources in devenv.sh environments.
