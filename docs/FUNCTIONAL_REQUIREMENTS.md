# Nix AI Model Plugin - Functional Requirements

## 1. Overview

### 1.1 Purpose
A Nix plugin/flake library for declaratively managing AI/ML models as reproducible, cacheable Nix derivations. Models are downloaded from standard interfaces (HuggingFace, MLFlow, Git LFS, HTTP/S3), verified, optionally post-processed, and stored in the Nix store for deterministic builds and deployments.

### 1.2 Goals
- **Reproducibility**: Pin models by hash for deterministic builds
- **Cacheability**: Leverage Nix store for deduplication and binary caches
- **Flexibility**: Support multiple model sources and verification methods
- **Security**: Enable post-download security scanning and verification
- **Integration**: Seamless use with HuggingFace transformers, vLLM, Ollama, etc.
- **Composability**: Work in system flakes, project flakes, dev shells, and CI/CD

---

## 2. Supported Model Sources

### 2.1 HuggingFace Hub
```nix
{
  source = "huggingface";
  repo = "meta-llama/Llama-2-7b-hf";  # org/model format
  revision = "main";                    # branch, tag, or commit SHA
  # Optional: specific files to download (default: all)
  files = [ "*.safetensors" "config.json" "tokenizer.json" ];
}
```

### 2.2 MLFlow Model Registry
```nix
{
  source = "mlflow";
  trackingUri = "https://mlflow.example.com";
  modelName = "my-fine-tuned-model";
  modelVersion = "3";  # or modelStage = "Production"
}
```

### 2.3 Git LFS Repositories
```nix
{
  source = "git-lfs";
  url = "https://github.com/org/model-repo.git";
  rev = "abc123...";  # commit SHA
  lfsFiles = [ "model.bin" "weights/*.pt" ];
}
```

### 2.4 Direct HTTP/HTTPS URLs
```nix
{
  source = "url";
  urls = [
    { url = "https://example.com/model.safetensors"; sha256 = "..."; }
    { url = "https://example.com/config.json"; sha256 = "..."; }
  ];
}
```

### 2.5 S3/GCS/Azure Blob Storage
```nix
{
  source = "s3";
  bucket = "my-models-bucket";
  prefix = "llama-2-7b/";
  region = "us-east-1";
  # Credentials via environment or Nix secrets
}
```

### 2.6 Ollama Registry
```nix
{
  source = "ollama";
  model = "llama2:7b";
}
```

---

## 3. Model Specification Schema

### 3.1 Core Configuration
```nix
{
  # Required
  name = "llama-2-7b";           # Derivation name
  source = { ... };               # One of the source types above

  # Integrity Verification (at least one required for reproducibility)
  hash = "sha256-...";            # Hash of entire output directory
  # OR per-file hashes
  fileHashes = {
    "model.safetensors" = "sha256-...";
    "config.json" = "sha256-...";
  };

  # Optional
  version = "1.0.0";              # Semantic version for your reference
  meta = {                        # Nix meta attributes
    description = "Llama 2 7B model";
    license = licenses.llama2;
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
```

### 3.2 Post-Download Hooks
```nix
{
  postDownload = {
    # Scripts run in order after download, before hash verification
    scripts = [
      {
        name = "security-scan";
        script = ''
          ${pkgs.modelscan}/bin/modelscan --path $out
        '';
        # If this script fails...
        onFailure = "abort";  # abort | warn | ignore
      }
      {
        name = "convert-to-safetensors";
        script = ''
          ${pkgs.python3}/bin/python ${./convert.py} $out
        '';
        onFailure = "abort";
      }
    ];

    # Environment variables available to scripts
    # $out        - output directory
    # $src        - source directory (before any transforms)
    # $MODEL_NAME - the model name
    # $MODEL_SIZE - total size in bytes
  };
}
```

### 3.3 Failure Handling
```nix
{
  onDownloadFailure = {
    # What to do with partial downloads
    action = "clean";          # clean | persist | retry

    # If persist, where to keep partial downloads for debugging
    persistPath = "/tmp/nix-model-failures";

    # Retry configuration
    maxRetries = 3;
    retryDelay = 5;            # seconds, with exponential backoff

    # Notify on failure (for CI/CD)
    notifyCommand = ''
      echo "Model download failed: $MODEL_NAME" | ${pkgs.curl}/bin/curl -X POST ...
    '';
  };
}
```

---

## 4. Integration Features

### 4.1 HuggingFace Cache Symlink
```nix
{
  integration.huggingface = {
    enable = true;
    # Creates symlinks so HuggingFace transformers can find models
    # ~/.cache/huggingface/hub/models--{org}--{model}/
    cacheDir = "~/.cache/huggingface/hub";
    # Or system-wide
    systemCacheDir = "/var/cache/huggingface";
  };
}
```

### 4.2 Environment Variables
```nix
{
  integration.environment = {
    # Set these env vars when the model is in scope
    HF_HOME = "${model}";
    TRANSFORMERS_CACHE = "${model}";
    # Custom vars
    MY_MODEL_PATH = "${model}/model.safetensors";
  };
}
```

### 4.3 Wrapper Scripts
```nix
{
  integration.wrappers = {
    # Generate wrapper scripts that set up the model path
    python = {
      enable = true;
      # Patches PYTHONPATH and sets HF_HOME
    };
    ollama = {
      enable = true;
      # Creates ollama-compatible model manifest
    };
  };
}
```

---

## 5. Flake Interface

### 5.1 As a Flake Input
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { self, nixpkgs, nix-ai-models, ... }: {
    # Use in packages
    packages.x86_64-linux.my-app = let
      llama = nix-ai-models.lib.fetchModel {
        source.huggingface = {
          repo = "meta-llama/Llama-2-7b-hf";
          revision = "main";
        };
        hash = "sha256-...";
      };
    in pkgs.writeShellApplication {
      name = "my-app";
      runtimeInputs = [ llama ];
      text = ''
        python app.py --model ${llama}
      '';
    };
  };
}
```

### 5.2 NixOS Module
```nix
{
  services.ai-models = {
    enable = true;
    models = {
      llama-2-7b = {
        source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
        hash = "sha256-...";
        integration.huggingface.enable = true;
      };
    };
    # System-wide cache directory
    cacheDir = "/var/cache/ai-models";
    # Users who can access models
    allowedUsers = [ "ml-user" "nginx" ];
  };
}
```

### 5.3 Home Manager Module
```nix
{
  programs.ai-models = {
    enable = true;
    models = {
      my-model = { ... };
    };
    # Per-user HuggingFace cache integration
    huggingfaceIntegration = true;
  };
}
```

---

## 6. CLI Tool (Optional)

### 6.1 Commands
```bash
# Prefetch a model and get its hash
nix-ai-model prefetch huggingface:meta-llama/Llama-2-7b-hf

# List cached models
nix-ai-model list

# Show model info
nix-ai-model info llama-2-7b

# Clean unused models
nix-ai-model gc

# Verify model integrity
nix-ai-model verify llama-2-7b

# Generate Nix expression from existing model
nix-ai-model to-nix ./my-model-dir
```

---

## 7. Security Features

### 7.1 Hash Verification
- SHA256 hash of entire output directory (FOD - Fixed Output Derivation)
- Per-file hash verification for large models
- Support for hash algorithms: sha256, sha512

### 7.2 Post-Download Scanning
```nix
{
  security = {
    # Built-in scanners
    enablePickleScan = true;      # Scan for malicious pickle files
    enableModelScan = true;       # Use modelscan tool

    # Custom scanners
    customScanners = [
      { name = "clamav"; command = "${pkgs.clamav}/bin/clamscan -r $out"; }
    ];

    # Fail if any scanner finds issues
    failOnScanError = true;
  };
}
```

### 7.3 Provenance Tracking
```nix
{
  provenance = {
    # Record download metadata
    recordSource = true;          # Where it came from
    recordTimestamp = true;       # When it was fetched
    signOutput = true;            # Sign with Nix key
  };
}
```

---

## 8. Advanced Features

### 8.1 Model Sharding
```nix
{
  # For models split across multiple files
  sharding = {
    enable = true;
    pattern = "model-*.safetensors";
    # Download shards in parallel
    parallelDownloads = 4;
  };
}
```

### 8.2 Quantization Support
```nix
{
  # Post-download quantization
  quantize = {
    enable = true;
    method = "gptq";              # gptq | awq | gguf
    bits = 4;
    # Outputs both original and quantized
    keepOriginal = false;
  };
}
```

### 8.3 Model Composition
```nix
{
  # Combine multiple model components
  compose = {
    base = fetchModel { ... };
    lora = fetchModel { ... };
    tokenizer = fetchModel { ... };
    # Merged into single output
  };
}
```

### 8.4 Lazy Fetching
```nix
{
  # Don't download until actually needed
  lazy = true;
  # Useful for large models in dev environments
}
```

---

## 9. Error Handling Matrix

| Failure Type | Default Action | Configurable Actions |
|--------------|----------------|---------------------|
| Network error during download | Retry 3x, then fail | retry, fail, persist-partial |
| Hash mismatch | Fail | fail, warn, update-hash |
| Post-download script fails | Fail | fail, warn, ignore, persist |
| Source not found | Fail | fail |
| Disk space exhausted | Fail | fail, persist-partial |
| Authentication failure | Fail | fail |

---

## 10. Logging and Observability

### 10.1 Build Logs
- Progress bars for large downloads
- Per-file download status
- Post-download script output
- Hash verification results

### 10.2 Structured Metadata
```nix
{
  # Output includes metadata file
  # $out/.nix-ai-model-meta.json
  {
    "name": "llama-2-7b",
    "source": "huggingface:meta-llama/Llama-2-7b-hf@main",
    "fetchedAt": "2024-01-15T10:30:00Z",
    "files": [...],
    "totalSize": 13000000000,
    "hash": "sha256-...",
    "postDownloadResults": [...]
  }
}
```

---

## 11. Use Case Examples

### 11.1 Production ML Service
```nix
# System flake for a production inference server
{
  services.vllm = {
    enable = true;
    model = nix-ai-models.lib.fetchModel {
      source.huggingface.repo = "meta-llama/Llama-2-70b-hf";
      hash = "sha256-abc123...";
      security.enableModelScan = true;
      onDownloadFailure.action = "clean";
    };
  };
}
```

### 11.2 Development Environment
```nix
# Project flake for development
{
  devShells.default = pkgs.mkShell {
    packages = [
      (nix-ai-models.lib.fetchModel {
        source.huggingface.repo = "microsoft/phi-2";
        hash = "sha256-...";
        integration.huggingface.enable = true;
      })
    ];
    shellHook = ''
      echo "Model available at: $PHI2_MODEL_PATH"
    '';
  };
}
```

### 11.3 CI/CD Pipeline
```nix
# Flake for testing with specific model version
{
  checks.x86_64-linux.model-tests = pkgs.runCommand "test" {
    model = fetchModel { ... };
  } ''
    python -c "from transformers import AutoModel; AutoModel.from_pretrained('$model')"
    touch $out
  '';
}
```

---

## 12. Non-Functional Requirements

### 12.1 Performance
- Parallel downloads for multi-file models
- Resume interrupted downloads (source-dependent)
- Efficient use of Nix binary cache

### 12.2 Compatibility
- Nix 2.4+ (flakes support)
- NixOS 23.05+
- Darwin (macOS) support
- Cross-platform model fetching

### 12.3 Documentation
- Comprehensive README
- API reference
- Common recipes and examples
- Troubleshooting guide

---

## 13. Open Questions

1. **Authentication**: How to handle HuggingFace tokens, MLFlow credentials, S3 keys?
   - Options: Environment variables, Nix secrets, agenix integration

2. **Large model handling**: Models >100GB may need special treatment
   - Options: Streaming verification, chunked downloads, local mirrors

3. **Version pinning**: How to handle model versions that change without new commits?
   - Options: Content addressing, timestamp-based snapshots

4. **Offline mode**: How to handle air-gapped environments?
   - Options: Pre-fetch to local cache, vendored models

---

## 14. Success Criteria

- [ ] Can fetch models from HuggingFace Hub with hash verification
- [ ] Can run post-download security scans
- [ ] Models are properly cached in Nix store
- [ ] HuggingFace transformers can load models via symlinks
- [ ] Failure handling works as configured
- [ ] Works in flakes, NixOS modules, and dev shells
- [ ] Documentation covers all use cases
