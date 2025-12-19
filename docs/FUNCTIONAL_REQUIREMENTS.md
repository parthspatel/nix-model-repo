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

## 2. Nix FOD Compliance & Validation Architecture

### 2.1 The FOD Constraint

Fixed Output Derivations (FODs) in Nix have strict constraints:
- **Network access only during fetch phase**
- **Output hash must be known upfront** (or use `outputHash = lib.fakeHash` for prefetching)
- **No arbitrary code execution** during the FOD build
- **Reproducibility**: Same hash must always produce identical output

This means: **Post-download hooks cannot run inside the FOD itself.**

### 2.2 Two-Phase Architecture

To remain FOD-compliant while supporting validation, we use a **two-derivation approach**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PHASE 1: FOD FETCH                          │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  fetchModel (FOD)                                            │   │
│  │  - Downloads model files from source                         │   │
│  │  - Verifies against known outputHash (sha256)                │   │
│  │  - NO code execution, NO validation                          │   │
│  │  - Output: /nix/store/<hash>-model-name-raw                  │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    PHASE 2: VALIDATION DERIVATION                    │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  validateModel (regular derivation)                          │   │
│  │  - Input: Phase 1 FOD output                                 │   │
│  │  - Runs security scanners (modelscan, pickle scan, etc.)     │   │
│  │  - Runs custom validation scripts                            │   │
│  │  - Creates HuggingFace-compatible directory structure        │   │
│  │  - Adds metadata file (.nix-ai-model-meta.json)              │   │
│  │  - Output: /nix/store/<hash>-model-name                      │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.3 Derivation Types by Use Case

| Use Case | Derivation Type | Hash Required? | Network Access |
|----------|-----------------|----------------|----------------|
| Production fetch (known hash) | FOD | Yes | Fetch phase only |
| Prefetch (discover hash) | FOD with `lib.fakeHash` | No (fails, shows hash) | Fetch phase only |
| Validation/scanning | Regular derivation | N/A (input is FOD) | None |
| Development (impure) | `__impure = true` | No | Full (unreproducible) |

### 2.4 Validation Hook Execution Model

```nix
{
  # Validation runs in Phase 2 (regular derivation)
  validation = {
    # Validators run in order; all must pass unless configured otherwise
    validators = [
      {
        name = "pickle-scan";
        # Runs against $src (the FOD output)
        command = "${pkgs.python3}/bin/python ${./scripts/pickle-scan.py} $src";
        # Validator behavior on failure
        onFailure = "abort";  # abort | warn | skip
        # Timeout for this validator
        timeout = 300;  # seconds
      }
      {
        name = "modelscan";
        command = "${pkgs.modelscan}/bin/modelscan --path $src";
        onFailure = "abort";
      }
      {
        name = "custom-check";
        command = "${./scripts/my-validator.sh} $src";
        onFailure = "warn";  # Log warning but continue
      }
    ];

    # If ANY validator with onFailure="abort" fails:
    # - The derivation fails
    # - No output is produced
    # - User must fix the issue or adjust validator config
  };
}
```

### 2.5 Transformations (Content-Modifying Hooks)

Transformations that modify model content **change the output hash**, so they're handled differently:

```nix
{
  # Transformations create a NEW derivation with a NEW hash
  transform = {
    # Each transformation produces a distinct store path
    steps = [
      {
        name = "convert-to-safetensors";
        command = "${pkgs.python3}/bin/python ${./convert.py} $src $out";
        # This transformation's output has its own hash
        outputHash = "sha256-...";  # Hash of transformed output
      }
    ];
  };
}
```

**Chain of derivations for transformed models:**
```
FOD (raw) → Validation → Transform → Final Output
   ↓            ↓            ↓            ↓
 hash1       (no hash)    hash2       hash2
```

### 2.6 Impure Mode (Development Only)

For development/experimentation where hashes aren't known:

```nix
{
  # WARNING: Not reproducible, not cacheable
  impure = true;

  # Allows:
  # - Fetching without known hash
  # - Running validators that need network (e.g., checking latest CVE database)
  # - Interactive debugging

  # Does NOT:
  # - Cache in binary caches
  # - Guarantee reproducibility
}
```

### 2.7 Hash Discovery Workflow

```bash
# Step 1: Attempt build with fake hash (will fail, but shows real hash)
$ nix build .#models.llama2
error: hash mismatch in fixed-output derivation:
  specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
  got:       sha256-abc123.....

# Step 2: Update flake.nix with real hash
# Step 3: Rebuild (now succeeds, is reproducible and cacheable)
```

---

## 3. Supported Model Sources

### 3.1 HuggingFace Hub
```nix
{
  source = "huggingface";
  repo = "meta-llama/Llama-2-7b-hf";  # org/model format
  revision = "main";                    # branch, tag, or commit SHA
  # Optional: specific files to download (default: all)
  files = [ "*.safetensors" "config.json" "tokenizer.json" ];
}
```

### 3.2 MLFlow Model Registry
```nix
{
  source = "mlflow";
  trackingUri = "https://mlflow.example.com";
  modelName = "my-fine-tuned-model";
  modelVersion = "3";  # or modelStage = "Production"
}
```

### 3.3 Git LFS Repositories
```nix
{
  source = "git-lfs";
  url = "https://github.com/org/model-repo.git";
  rev = "abc123...";  # commit SHA
  lfsFiles = [ "model.bin" "weights/*.pt" ];
}
```

### 3.4 Direct HTTP/HTTPS URLs
```nix
{
  source = "url";
  urls = [
    { url = "https://example.com/model.safetensors"; sha256 = "..."; }
    { url = "https://example.com/config.json"; sha256 = "..."; }
  ];
}
```

### 3.5 S3/GCS/Azure Blob Storage
```nix
{
  source = "s3";
  bucket = "my-models-bucket";
  prefix = "llama-2-7b/";
  region = "us-east-1";
  # Credentials via environment or Nix secrets
}
```

### 3.6 Ollama Registry
```nix
{
  source = "ollama";
  model = "llama2:7b";
}
```

---

## 4. Authentication Specification

### 4.1 Authentication Architecture

Authentication is handled **outside the FOD** via impure environment variables or file-based credentials, passed into the fetch phase.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CREDENTIAL FLOW                                   │
│                                                                      │
│  User Environment          Nix Build               Model Source     │
│  ─────────────────         ─────────               ────────────     │
│                                                                      │
│  HF_TOKEN (env var)  ───►  FOD Builder  ───────►  HuggingFace API   │
│       or                   (impure access         (authenticated)   │
│  ~/.cache/huggingface/     to env/files)                            │
│    token                                                             │
│       or                                                             │
│  Nix secrets ──────────►   Decrypted at          AWS/GCS/Azure      │
│  (sops/agenix)             build time                               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 Credential Sources (Priority Order)

```nix
{
  auth = {
    # Priority 1: Explicit token in config (NOT RECOMMENDED - stored in Nix store)
    # token = "hf_xxxxx";  # DANGER: visible in /nix/store

    # Priority 2: Environment variable name
    tokenEnvVar = "HF_TOKEN";  # default

    # Priority 3: File path (outside Nix store)
    tokenFile = "/run/secrets/huggingface-token";  # e.g., from agenix/sops

    # Priority 4: Standard HuggingFace token location
    useHfCli = true;  # reads ~/.cache/huggingface/token

    # For cloud providers
    awsProfile = "ml-models";           # AWS credentials profile
    gcpServiceAccountKey = "/run/secrets/gcp-sa.json";
  };
}
```

### 4.3 Gated Models (HuggingFace)

Gated models require users to accept license terms on huggingface.co before downloading.

**Workflow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GATED MODEL ACCESS FLOW                           │
│                                                                      │
│  1. User visits huggingface.co/meta-llama/Llama-2-7b-hf              │
│                          │                                           │
│                          ▼                                           │
│  2. User clicks "Accept License" (one-time, stored in HF account)   │
│                          │                                           │
│                          ▼                                           │
│  3. User generates access token at huggingface.co/settings/tokens   │
│     (must have "read" scope for gated models)                       │
│                          │                                           │
│                          ▼                                           │
│  4. Token is stored locally:                                         │
│     - huggingface-cli login                                          │
│     - OR: export HF_TOKEN=hf_xxxxx                                  │
│     - OR: /run/secrets/hf-token (via sops/agenix)                   │
│                          │                                           │
│                          ▼                                           │
│  5. nix build fetches model using token                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Nix Configuration for Gated Models:**

```nix
{
  source.huggingface = {
    repo = "meta-llama/Llama-2-7b-hf";
    revision = "main";
  };

  auth = {
    # Gated models REQUIRE a token
    required = true;

    # Error message if token is missing or access denied
    gatedModelHelp = ''
      This is a gated model. To access it:
      1. Visit https://huggingface.co/meta-llama/Llama-2-7b-hf
      2. Accept the license agreement
      3. Generate a token at https://huggingface.co/settings/tokens
      4. Run: export HF_TOKEN=your_token_here
    '';
  };

  # Hash still required for reproducibility
  hash = "sha256-...";
}
```

### 4.4 Token Refresh for Long Downloads

Large models (100GB+) may take hours to download. Tokens can expire mid-download.

**Strategies:**

| Strategy | Description | When to Use |
|----------|-------------|-------------|
| Long-lived tokens | HuggingFace tokens don't expire by default | Default for HF |
| Token refresh hook | Script to refresh token periodically | OAuth/OIDC flows |
| Download resume | Resume with new token if expired | All sources |
| Chunked downloads | Smaller requests, each authenticated | Large models |

**Token Refresh Configuration:**

```nix
{
  auth = {
    # For sources with expiring tokens (e.g., OAuth, STS)
    tokenRefresh = {
      enable = true;

      # Command to get a fresh token (stdout = new token)
      command = "${pkgs.awscli2}/bin/aws sts get-session-token --query Token";

      # Refresh before expiry
      refreshBeforeExpirySec = 300;  # 5 minutes before expiry

      # Maximum token lifetime (for sources that don't report expiry)
      maxTokenAgeSec = 3600;  # 1 hour
    };

    # Or: Script that handles authentication entirely
    authScript = ''
      # Custom auth logic
      # Must output: export AUTH_HEADER="Bearer xxx"
      ${pkgs.vault}/bin/vault read -field=token secret/ml/hf-token
    '';
  };
}
```

**Resume on Token Expiry:**

```nix
{
  download = {
    # If download fails due to 401/403, attempt token refresh and resume
    resumeOnAuthFailure = true;

    # Maximum resume attempts
    maxResumeAttempts = 3;

    # Checkpointing for resumable downloads
    enableCheckpoints = true;
    checkpointIntervalMB = 1000;  # Save progress every 1GB
  };
}
```

### 4.5 Credential Isolation & Security

**Threat Model:**

| Threat | Mitigation |
|--------|------------|
| Token in Nix store (world-readable) | Never store tokens in derivation; use impure env vars |
| Token in build logs | Mask tokens in output; use `--quiet` for sensitive commands |
| Token leaked to other builds | Sandboxed builds; token only available to specific FOD |
| Token stolen from memory | Short-lived tokens; minimal token scope |
| Token in shell history | Use token files, not command-line args |

**Secure Configuration:**

```nix
{
  auth = {
    # NEVER do this (token visible in /nix/store):
    # token = "hf_xxxxx";

    # GOOD: Environment variable (not stored in Nix)
    tokenEnvVar = "HF_TOKEN";

    # BETTER: File outside Nix store
    tokenFile = "/run/secrets/hf-token";

    # BEST: Integration with secrets management
    sops.secretFile = ./secrets/hf-token.yaml;
    # or
    agenix.secretFile = ./secrets/hf-token.age;
  };

  # Credential isolation settings
  security = {
    # Mask tokens in build output
    maskSecretsInLogs = true;

    # Don't pass credentials to post-download hooks
    isolateCredentialsFromHooks = true;

    # Verify token has minimum required scopes
    requiredScopes = [ "read" ];  # HuggingFace token scopes

    # Warn if token has excessive permissions
    warnOnExcessiveScopes = true;
  };
}
```

**Nix Sandbox Considerations:**

```nix
{
  # FODs have network access but limited filesystem access
  # Credentials must be passed via:

  # 1. Impure environment variables (requires --impure or trusted config)
  impureEnvVars = [ "HF_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" ];

  # 2. Or via Nix's built-in netrc support for HTTP basic auth
  netrcFile = "/etc/nix/netrc";  # Contains: machine huggingface.co login user password TOKEN

  # 3. Or via passthru for evaluated-but-not-stored secrets
  # (Advanced: requires careful handling)
}
```

### 4.6 Per-Source Authentication Reference

| Source | Auth Method | Token Location | Notes |
|--------|-------------|----------------|-------|
| HuggingFace | Bearer token | `HF_TOKEN` env or `~/.cache/huggingface/token` | Gated models need license acceptance |
| MLFlow | Various | Depends on backend | Often uses HTTP Basic or OAuth |
| Git LFS | Git credentials | `~/.git-credentials` or SSH keys | Standard Git auth |
| S3 | AWS credentials | `~/.aws/credentials` or env vars | IAM roles preferred in cloud |
| GCS | Service account | `GOOGLE_APPLICATION_CREDENTIALS` | Workload identity in GKE |
| Azure Blob | SAS token or AD | `AZURE_STORAGE_*` env vars | Managed identity preferred |
| Ollama | None | N/A | Public registry, no auth |

### 4.7 CI/CD Authentication Patterns

**GitHub Actions:**

```yaml
jobs:
  build:
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - name: Build with model
        env:
          HF_TOKEN: ${{ secrets.HF_TOKEN }}
        run: nix build .#my-model-app --impure
```

**GitLab CI:**

```yaml
build:
  script:
    - nix build .#my-model-app --impure
  variables:
    HF_TOKEN: $HF_TOKEN  # From CI/CD variables (masked)
```

**NixOS System Build:**

```nix
# /etc/nixos/configuration.nix
{
  # For system-level model fetching during nixos-rebuild
  nix.settings.extra-sandbox-paths = [
    "/run/secrets/hf-token"
  ];

  # With agenix
  age.secrets.hf-token = {
    file = ./secrets/hf-token.age;
    mode = "0400";
  };
}
```

---

## 5. Model Specification Schema

### 5.1 Core Configuration
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

### 5.2 Post-Download Hooks
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

### 5.3 Failure Handling
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

## 6. HuggingFace Cache Structure & Integration

### 6.1 HuggingFace Hub Cache Layout

The HuggingFace `transformers` and `huggingface_hub` libraries expect a specific directory structure. Our plugin must create this structure for seamless integration.

**Standard HuggingFace Cache Structure:**

```
~/.cache/huggingface/hub/
├── models--meta-llama--Llama-2-7b-hf/
│   ├── .no_exist/                    # Markers for files that don't exist
│   │   └── main/                     # Per-revision markers
│   ├── blobs/
│   │   ├── 3a0f8...                  # SHA256 hash of file content
│   │   ├── 7c2b1...                  # Each blob is content-addressed
│   │   └── ...                       # Large files stored here
│   ├── refs/
│   │   └── main                      # Text file containing commit SHA
│   └── snapshots/
│       └── a1b2c3d4e5f6.../          # Commit SHA directory
│           ├── config.json           # Symlink → ../../blobs/3a0f8...
│           ├── tokenizer.json        # Symlink → ../../blobs/7c2b1...
│           ├── model.safetensors     # Symlink → ../../blobs/...
│           └── ...
├── models--microsoft--phi-2/
│   └── ...
└── version.txt                       # Cache version (currently "1")
```

### 6.2 How Transformers Resolves Models

```
┌─────────────────────────────────────────────────────────────────────┐
│              HUGGINGFACE MODEL RESOLUTION FLOW                       │
│                                                                      │
│  AutoModel.from_pretrained("meta-llama/Llama-2-7b-hf")              │
│                          │                                           │
│                          ▼                                           │
│  1. Check HF_HOME or ~/.cache/huggingface/hub                       │
│                          │                                           │
│                          ▼                                           │
│  2. Look for: models--meta-llama--Llama-2-7b-hf/                    │
│                          │                                           │
│                          ▼                                           │
│  3. Read refs/main → get commit SHA (e.g., "a1b2c3d4...")           │
│                          │                                           │
│                          ▼                                           │
│  4. Access snapshots/a1b2c3d4.../                                   │
│                          │                                           │
│                          ▼                                           │
│  5. Follow symlinks to blobs/ for actual file content               │
│                          │                                           │
│                          ▼                                           │
│  6. Load model files (config.json, *.safetensors, etc.)             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.3 Nix Store to HuggingFace Cache Mapping

Our plugin creates a structure in the Nix store that can be symlinked into the HuggingFace cache:

```nix
# Nix store output structure:
# /nix/store/<hash>-llama-2-7b-hf/
# ├── blobs/
# │   ├── <sha256-of-config.json>
# │   └── <sha256-of-model.safetensors>
# ├── refs/
# │   └── main                         # Contains: "abc123def456..."
# ├── snapshots/
# │   └── abc123def456.../
# │       ├── config.json              # Symlink → ../../blobs/...
# │       └── model.safetensors        # Symlink → ../../blobs/...
# └── .nix-ai-model-meta.json          # Our metadata

{
  integration.huggingface = {
    enable = true;

    # Creates this symlink structure:
    # ~/.cache/huggingface/hub/models--meta-llama--Llama-2-7b-hf
    #   → /nix/store/<hash>-llama-2-7b-hf

    # Override cache location (default: ~/.cache/huggingface/hub)
    cacheDir = null;  # Uses HF_HOME or default

    # For system-wide installation
    systemCacheDir = "/var/cache/huggingface/hub";

    # Model naming in cache
    org = "meta-llama";      # Extracted from repo if not specified
    model = "Llama-2-7b-hf"; # Extracted from repo if not specified

    # Which refs to create
    refs = [ "main" ];       # Default: just "main"
    # refs = [ "main" "v1.0" "abc123..." ];  # Multiple refs
  };
}
```

### 6.4 Symlink Creation Strategies

| Strategy | Description | Pros | Cons |
|----------|-------------|------|------|
| **Direct symlink** | Link model dir → Nix store | Simple, immediate | Requires write access to cache |
| **Activation script** | Create symlinks on shell enter | Works per-project | Only in dev shells |
| **NixOS module** | System-wide symlink management | Persistent, system-wide | Requires rebuild |
| **Home Manager** | Per-user symlink management | Per-user, declarative | Requires home-manager |
| **Wrapper script** | Set HF_HOME to Nix store | No symlinks needed | App-specific |

**Activation Script Example (for devShells):**

```nix
{
  devShells.default = pkgs.mkShell {
    packages = [ llama-model ];
    shellHook = ''
      # Create HuggingFace cache structure
      mkdir -p ~/.cache/huggingface/hub

      # Symlink model into cache
      ln -sfn ${llama-model} \
        ~/.cache/huggingface/hub/models--meta-llama--Llama-2-7b-hf

      echo "Model available: meta-llama/Llama-2-7b-hf"
    '';
  };
}
```

**Wrapper Script Example (no symlinks needed):**

```nix
{
  # Wrap python to use Nix store directly as HF cache
  pythonWithModel = pkgs.writeShellScriptBin "python-with-llama" ''
    export HF_HOME="${llama-model}"
    export TRANSFORMERS_CACHE="${llama-model}"
    exec ${pkgs.python3}/bin/python "$@"
  '';
}
```

### 6.5 Blob Deduplication

HuggingFace uses content-addressed storage (blobs). We leverage this for deduplication:

```nix
{
  # Two models sharing the same tokenizer
  llama-7b = fetchModel { ... };  # Has tokenizer.json (sha256: abc123)
  llama-13b = fetchModel { ... }; # Same tokenizer.json (sha256: abc123)

  # In Nix store, each model has its own copy
  # But in HuggingFace cache, blobs are shared:
  # ~/.cache/huggingface/hub/
  # ├── models--meta-llama--Llama-2-7b-hf/blobs/abc123 → /nix/store/.../abc123
  # └── models--meta-llama--Llama-2-13b-hf/blobs/abc123 → (same target)
}
```

### 6.6 Offline Mode Compatibility

```nix
{
  integration.huggingface = {
    enable = true;

    # Mark as "already downloaded" so transformers doesn't try to fetch
    markComplete = true;

    # Disable online checks
    offlineMode = true;  # Sets HF_HUB_OFFLINE=1

    # Ensure all required files are present
    validateCompleteness = true;
  };
}
```

**Environment Variables for Offline Use:**

```bash
export HF_HUB_OFFLINE=1           # Don't try to download
export TRANSFORMERS_OFFLINE=1     # Legacy variable
export HF_DATASETS_OFFLINE=1      # For datasets too
```

### 6.7 Version/Ref Management

```nix
{
  # Pin to specific commit
  source.huggingface = {
    repo = "meta-llama/Llama-2-7b-hf";
    revision = "abc123def456...";  # Full commit SHA
  };

  integration.huggingface = {
    # Create ref pointing to this commit
    refs = [
      { name = "main"; sha = "abc123def456..."; }
      # Can also create version tags
      { name = "v1.0.0"; sha = "abc123def456..."; }
    ];
  };
}
```

---

## 7. Integration Features

### 7.1 Environment Variables
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

### 7.2 Wrapper Scripts
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

## 8. Flake Interface

### 8.1 As a Flake Input
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

### 8.2 NixOS Module
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

### 8.3 Home Manager Module
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

## 9. CLI Tool (Optional)

### 9.1 Commands
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

## 10. Security Features

### 10.1 Hash Verification
- SHA256 hash of entire output directory (FOD - Fixed Output Derivation)
- Per-file hash verification for large models
- Support for hash algorithms: sha256, sha512

### 10.2 Post-Download Scanning
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

### 10.3 Provenance Tracking
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

## 11. Advanced Features

### 11.1 Model Sharding
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

### 11.2 Quantization Support
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

### 11.3 Model Composition
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

### 11.4 Lazy Fetching
```nix
{
  # Don't download until actually needed
  lazy = true;
  # Useful for large models in dev environments
}
```

---

## 12. Error Handling Matrix

| Failure Type | Default Action | Configurable Actions |
|--------------|----------------|---------------------|
| Network error during download | Retry 3x, then fail | retry, fail, persist-partial |
| Hash mismatch | Fail | fail, warn, update-hash |
| Post-download script fails | Fail | fail, warn, ignore, persist |
| Source not found | Fail | fail |
| Disk space exhausted | Fail | fail, persist-partial |
| Authentication failure | Fail | fail |

---

## 13. Logging and Observability

### 13.1 Build Logs
- Progress bars for large downloads
- Per-file download status
- Post-download script output
- Hash verification results

### 13.2 Structured Metadata
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

## 14. Use Case Examples

### 14.1 Production ML Service
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

### 14.2 Development Environment
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

### 14.3 CI/CD Pipeline
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

## 15. Non-Functional Requirements

### 15.1 Performance
- Parallel downloads for multi-file models
- Resume interrupted downloads (source-dependent)
- Efficient use of Nix binary cache

### 15.2 Compatibility
- Nix 2.4+ (flakes support)
- NixOS 23.05+
- Darwin (macOS) support
- Cross-platform model fetching

### 15.3 Documentation
- Comprehensive README
- API reference
- Common recipes and examples
- Troubleshooting guide

---

## 16. Open Questions

1. **Authentication**: How to handle HuggingFace tokens, MLFlow credentials, S3 keys?
   - Options: Environment variables, Nix secrets, agenix integration

2. **Large model handling**: Models >100GB may need special treatment
   - Options: Streaming verification, chunked downloads, local mirrors

3. **Version pinning**: How to handle model versions that change without new commits?
   - Options: Content addressing, timestamp-based snapshots

4. **Offline mode**: How to handle air-gapped environments?
   - Options: Pre-fetch to local cache, vendored models

---

## 17. Success Criteria

- [ ] Can fetch models from HuggingFace Hub with hash verification
- [ ] Can run post-download security scans
- [ ] Models are properly cached in Nix store
- [ ] HuggingFace transformers can load models via symlinks
- [ ] Failure handling works as configured
- [ ] Works in flakes, NixOS modules, and dev shells
- [ ] Documentation covers all use cases
