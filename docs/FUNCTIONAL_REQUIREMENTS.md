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

## 12. Network Configuration

### 12.1 Bandwidth Throttling

Control download speeds to avoid saturating network or triggering rate limits:

```nix
{
  network = {
    # Bandwidth limiting
    bandwidth = {
      # Maximum download speed (bytes/sec, or use suffixes: K, M, G)
      limit = "50M";              # 50 MB/s max
      # Or unlimited
      limit = null;               # No limit (default)

      # Per-connection limit (for parallel downloads)
      perConnectionLimit = "10M"; # Each parallel download limited to 10 MB/s

      # Burst allowance (allow temporary spikes above limit)
      burstSize = "100M";         # Allow bursts up to 100MB before throttling
    };
  };
}
```

### 12.2 Timeout Configuration

```nix
{
  network = {
    timeouts = {
      # Connection timeout (time to establish connection)
      connect = 30;               # seconds (default: 30)

      # Read timeout (max time between data packets)
      read = 300;                 # seconds (default: 300 = 5 min)

      # Total download timeout (0 = unlimited)
      total = 0;                  # seconds (default: 0 for large models)

      # Or calculate based on expected size
      totalPerGB = 600;           # 10 minutes per GB expected

      # Stall detection (abort if no progress)
      stallTimeout = 120;         # Abort if no bytes received for 2 minutes
      stallMinSpeed = "10K";      # Or if speed drops below 10 KB/s for stallTimeout
    };
  };
}
```

### 12.3 Proxy Configuration

```nix
{
  network = {
    proxy = {
      # HTTP proxy
      http = "http://proxy.example.com:8080";

      # HTTPS proxy (often same as HTTP)
      https = "http://proxy.example.com:8080";

      # No proxy for specific hosts
      noProxy = [ "localhost" "127.0.0.1" "*.internal.example.com" ];

      # Or inherit from environment
      useEnvironment = true;      # Use HTTP_PROXY, HTTPS_PROXY, NO_PROXY env vars

      # Proxy authentication
      auth = {
        # Username/password (NOT RECOMMENDED - use env vars)
        # username = "user";
        # password = "pass";

        # Or via environment variables
        usernameEnvVar = "PROXY_USER";
        passwordEnvVar = "PROXY_PASS";
      };

      # SOCKS proxy support
      socks = {
        enable = false;
        url = "socks5://proxy.example.com:1080";
        version = 5;              # SOCKS4 or SOCKS5
      };
    };

    # SSL/TLS configuration
    tls = {
      # Custom CA certificate bundle
      caBundle = "/etc/ssl/certs/ca-certificates.crt";

      # Skip certificate verification (DANGEROUS - dev only)
      insecure = false;

      # Minimum TLS version
      minVersion = "1.2";         # TLS 1.2 minimum (default)
    };
  };
}
```

### 12.4 Retry Configuration

```nix
{
  network = {
    retry = {
      # Maximum retry attempts for transient failures
      maxAttempts = 5;            # default: 3

      # Base delay between retries (exponential backoff)
      baseDelay = 2;              # seconds
      maxDelay = 60;              # cap at 1 minute

      # Jitter to prevent thundering herd
      jitter = 0.25;              # ±25% randomization

      # Which errors to retry
      retryOn = [
        "connection_timeout"
        "connection_reset"
        "dns_failure"
        "http_5xx"                # Server errors
        "http_429"                # Rate limited
      ];

      # Don't retry these
      noRetryOn = [
        "http_401"                # Auth failure (need new token)
        "http_403"                # Forbidden
        "http_404"                # Not found
        "hash_mismatch"           # Content changed upstream
      ];
    };
  };
}
```

---

## 13. Resource Management

### 13.1 Disk Space Pre-Checks

Validate sufficient disk space before starting downloads to avoid partial failures:

```nix
{
  resources = {
    disk = {
      # Pre-flight disk space check
      preCheck = {
        enable = true;            # default: true

        # Minimum free space to maintain after download
        minFreeSpace = "10G";     # Always keep 10GB free

        # Or as percentage of total disk
        minFreePercent = 5;       # Always keep 5% free

        # Estimated model size (if not provided by source)
        estimatedSize = null;     # Auto-detect from Content-Length or manifest

        # Safety margin multiplier for estimated size
        sizeMargin = 1.2;         # Require 20% more than estimated (for temp files)
      };

      # Behavior when disk space is low
      onLowSpace = {
        # Before download starts
        preDownload = "abort";    # abort | warn | ignore

        # During download (monitoring)
        duringDownload = {
          enable = true;
          checkInterval = 60;     # Check every 60 seconds
          action = "abort";       # abort | pause | warn
        };
      };
    };
  };
}
```

**Disk Space Check Flow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DISK SPACE VALIDATION FLOW                        │
│                                                                      │
│  1. Query model size from source                                    │
│     - HuggingFace: API returns file sizes                           │
│     - HTTP: HEAD request for Content-Length                         │
│     - Git LFS: Parse .gitattributes + LFS pointers                  │
│                          │                                           │
│                          ▼                                           │
│  2. Calculate required space                                        │
│     required = (model_size × sizeMargin) + minFreeSpace             │
│                          │                                           │
│                          ▼                                           │
│  3. Check available space on target volume                          │
│     available = df $TMPDIR or $NIX_BUILD_TOP                        │
│                          │                                           │
│                          ▼                                           │
│  4. Compare and decide                                              │
│     if available < required:                                        │
│       → abort with helpful error message                            │
│       → suggest: nix-collect-garbage, clear temp, etc.              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Error Message Example:**

```
error: Insufficient disk space for model download

  Model:           meta-llama/Llama-2-70b-hf
  Required:        145.2 GB (130.2 GB model + 10 GB minimum free + 5 GB margin)
  Available:       89.4 GB
  Shortfall:       55.8 GB

  Suggestions:
    • Run: nix-collect-garbage -d
    • Clear temp files: rm -rf /tmp/nix-build-*
    • Use a different volume: export TMPDIR=/mnt/large-disk/tmp
    • Download individual files: files = [ "config.json" "tokenizer.json" ]
```

### 13.2 Rate Limiting

Per-source rate limiting to respect API limits and avoid bans:

```nix
{
  resources = {
    rateLimit = {
      # Global rate limit (across all sources)
      global = {
        requestsPerMinute = 60;   # Max 60 requests/min total
        requestsPerHour = null;   # No hourly limit
      };

      # Per-source limits (override global)
      perSource = {
        huggingface = {
          # HuggingFace Hub API limits (built-in defaults)
          requestsPerMinute = 30;
          requestsPerHour = 500;

          # Concurrent connections to same host
          maxConnections = 4;

          # Special handling for gated models (stricter limits)
          gatedModels = {
            requestsPerMinute = 10;
            maxConnections = 2;
          };
        };

        s3 = {
          # S3 has high limits but costs money per request
          requestsPerMinute = 100;
          maxConnections = 10;
        };

        github = {
          # GitHub API rate limits
          requestsPerMinute = 30;  # Unauthenticated
          requestsPerHour = 60;
          # With token: 5000/hour
          authenticatedRequestsPerHour = 5000;
        };

        ollama = {
          # Ollama registry (generous limits)
          requestsPerMinute = 60;
          maxConnections = 4;
        };

        # Custom/self-hosted
        custom = {
          requestsPerMinute = 30;  # Conservative default
          maxConnections = 2;
        };
      };

      # Behavior when rate limited
      onRateLimit = {
        # When we hit our self-imposed limit
        selfLimited = "wait";     # wait | abort

        # When server returns 429
        serverLimited = {
          action = "wait";        # wait | abort
          respectRetryAfter = true; # Honor Retry-After header
          maxWait = 300;          # Max wait time (seconds), abort if longer
        };
      };

      # Rate limit persistence (remember limits across builds)
      persistence = {
        enable = true;
        stateFile = "/var/cache/nix-ai-models/rate-limit-state.json";
      };
    };
  };
}
```

**Built-in Rate Limit Defaults:**

| Source | Requests/min | Requests/hour | Max Connections | Notes |
|--------|--------------|---------------|-----------------|-------|
| HuggingFace (public) | 30 | 500 | 4 | Conservative for shared IPs |
| HuggingFace (gated) | 10 | 100 | 2 | Stricter for licensed models |
| HuggingFace (auth) | 60 | 1000 | 8 | With valid HF_TOKEN |
| GitHub LFS | 30 | 60 | 4 | Unauthenticated |
| GitHub LFS (auth) | 100 | 5000 | 8 | With GITHUB_TOKEN |
| S3/GCS/Azure | 100 | ∞ | 10 | Cloud limits are very high |
| Ollama | 60 | ∞ | 4 | Self-hosted friendly |
| HTTP (generic) | 30 | 500 | 2 | Conservative default |

---

## 14. Concurrent Downloads

### 14.1 Parallel Download Configuration

```nix
{
  download = {
    parallel = {
      # Enable parallel downloads for multi-file models
      enable = true;

      # Maximum concurrent file downloads
      maxConcurrent = 4;          # default: 4

      # Per-file chunked parallel download (for large single files)
      chunked = {
        enable = true;
        minFileSize = "100M";     # Only chunk files > 100MB
        chunkSize = "50M";        # Download in 50MB chunks
        maxChunksPerFile = 8;     # Max 8 parallel chunks per file
      };

      # Priority ordering
      priority = {
        # Download these files first (needed for validation)
        high = [ "config.json" "tokenizer.json" "tokenizer_config.json" ];
        # Download these last (largest files)
        low = [ "*.safetensors" "*.bin" "*.gguf" ];
      };
    };
  };
}
```

### 14.2 Coordination Between Builds

Handle multiple Nix builds trying to fetch the same model:

```nix
{
  download = {
    coordination = {
      # Lock file to prevent duplicate downloads
      locking = {
        enable = true;

        # Lock scope
        scope = "global";         # global | per-user | per-build

        # Lock file location
        lockDir = "/var/lock/nix-ai-models";

        # Lock timeout (wait for other build to finish)
        timeout = 3600;           # 1 hour max wait

        # If lock held, check if holder is still alive
        staleTimeout = 300;       # Consider stale after 5 min no activity
      };

      # Shared download cache (outside Nix store)
      sharedCache = {
        enable = true;

        # Temporary cache for in-progress downloads
        tempDir = "/var/cache/nix-ai-models/downloads";

        # Completed downloads waiting to be copied to Nix store
        stagingDir = "/var/cache/nix-ai-models/staging";

        # Cache permissions
        mode = "0755";            # World-readable
        group = "nixbld";         # Nix build group
      };
    };
  };
}
```

**Coordination Flow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CONCURRENT DOWNLOAD COORDINATION                  │
│                                                                      │
│  Build A starts: fetchModel { repo = "llama/7b"; hash = "sha256-x" }│
│                          │                                           │
│                          ▼                                           │
│  1. Acquire lock: /var/lock/nix-ai-models/sha256-x.lock             │
│     → Lock acquired (first to request)                              │
│                          │                                           │
│  Build B starts: fetchModel { repo = "llama/7b"; hash = "sha256-x" }│
│                          │                                           │
│                          ▼                                           │
│  2. Try acquire lock → BLOCKED                                      │
│     → Wait for Build A to complete                                  │
│                          │                                           │
│  Build A completes:      │                                           │
│  3. Download → staging → Nix store                                  │
│  4. Release lock                                                    │
│                          │                                           │
│                          ▼                                           │
│  Build B unblocked:                                                 │
│  5. Check Nix store → Model already exists!                         │
│  6. Return cached path (no download needed)                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 15. Binary Cache Compatibility

### 15.1 Cachix & Attic Integration

Models must work with Nix binary caches for team/CI sharing:

```nix
{
  cache = {
    # Ensure compatibility with binary caches
    compatibility = {
      # Maximum single file size for cache upload
      # Cachix: 2GB per NAR, Attic: configurable
      maxNarSize = "2G";          # Warn if NAR exceeds this

      # Chunking strategy for large models
      chunking = {
        enable = true;

        # Split large models into multiple store paths
        strategy = "by-file";     # by-file | by-size | none

        # Maximum size per chunk (for by-size)
        maxChunkSize = "1G";

        # Minimum files per chunk (for by-file, avoid too many small paths)
        minFilesPerChunk = 5;
      };

      # Compression settings (match cache server)
      compression = {
        # NAR compression for upload
        algorithm = "zstd";       # zstd | xz | none
        level = 8;                # 1-19 for zstd (default: 8)

        # Skip compression for already-compressed files
        skipPatterns = [ "*.safetensors" "*.gguf" "*.bin" ];
      };
    };

    # Push configuration
    push = {
      # Automatically push to cache after successful fetch
      auto = false;               # Opt-in (can be slow for large models)

      # Cache targets
      targets = [
        {
          name = "cachix";
          url = "https://mycache.cachix.org";
          # Auth via CACHIX_AUTH_TOKEN env var
        }
        {
          name = "attic";
          url = "https://attic.example.com/ml-models";
          # Auth via ATTIC_TOKEN env var
        }
      ];

      # Push filters
      filter = {
        # Only push models matching these patterns
        include = [ "*" ];
        # Never push these (e.g., proprietary models)
        exclude = [ "*llama*" "*gpt*" ];
      };
    };
  };
}
```

### 15.2 NAR Size Considerations

```
┌─────────────────────────────────────────────────────────────────────┐
│                    BINARY CACHE SIZE LIMITS                          │
│                                                                      │
│  Service          Max NAR Size    Max Total Storage                 │
│  ───────────────────────────────────────────────────────────────   │
│  Cachix (free)    2 GB            10 GB                             │
│  Cachix (paid)    2 GB            Unlimited                         │
│  Attic            Configurable    Configurable                      │
│  nix-serve        Unlimited       Disk-limited                      │
│  S3 (custom)      5 GB (S3 limit) Unlimited                         │
│                                                                      │
│  Challenge: Llama-70B = 130GB+ → Won't fit in single NAR            │
│                                                                      │
│  Solution: Chunked store paths                                       │
│  /nix/store/xxx-llama-70b-meta/    (config, tokenizer - small)      │
│  /nix/store/xxx-llama-70b-shard-1/ (model-00001.safetensors)        │
│  /nix/store/xxx-llama-70b-shard-2/ (model-00002.safetensors)        │
│  ...                                                                 │
│  /nix/store/xxx-llama-70b/         (combines all, symlinks)         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 15.3 Chunked Model Architecture

```nix
{
  # For very large models, split into multiple derivations
  # This happens automatically based on cache.compatibility.chunking

  # User-facing: single fetchModel call
  llama-70b = fetchModel {
    source.huggingface.repo = "meta-llama/Llama-2-70b-hf";
    hash = "sha256-...";           # Hash of final combined output

    cache.chunking = {
      enable = true;
      strategy = "by-file";
    };
  };

  # Internally creates:
  # - llama-70b-meta   (config.json, tokenizer.*, etc.)
  # - llama-70b-00001  (model-00001-of-00015.safetensors)
  # - llama-70b-00002  (model-00002-of-00015.safetensors)
  # - ...
  # - llama-70b        (combines all shards via symlinks)

  # Benefits:
  # - Each shard is independently cacheable
  # - Parallel upload/download from binary cache
  # - Partial cache hits (some shards cached, others not)
  # - Shard reuse across model versions (if files unchanged)
}
```

### 15.4 Cache Verification

```nix
{
  cache = {
    verification = {
      # Verify cached models haven't been tampered with
      enable = true;

      # Re-verify hash on cache hit
      verifyOnUse = true;         # default: true

      # Sign models with cache key
      sign = {
        enable = true;
        keyFile = "/etc/nix/cache-key.sec";
      };

      # Require signature for cached models
      requireSignature = false;   # default: false (for public models)
    };
  };
}
```

---

## 16. Error Handling Matrix

| Failure Type | Default Action | Configurable Actions |
|--------------|----------------|---------------------|
| Network error during download | Retry 3x, then fail | retry, fail, persist-partial |
| Hash mismatch | Fail | fail, warn, update-hash |
| Post-download script fails | Fail | fail, warn, ignore, persist |
| Source not found | Fail | fail |
| Disk space exhausted | Fail | fail, persist-partial |
| Authentication failure | Fail | fail |

---

## 17. Logging and Observability

### 17.1 Build Logs
- Progress bars for large downloads
- Per-file download status
- Post-download script output
- Hash verification results

### 17.2 Structured Metadata
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

## 18. Use Case Examples

### 18.1 Production ML Service
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

### 18.2 Development Environment
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

### 18.3 CI/CD Pipeline
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

## 19. Non-Functional Requirements

### 19.1 Performance
- Parallel downloads for multi-file models
- Resume interrupted downloads (source-dependent)
- Efficient use of Nix binary cache

### 19.2 Compatibility
- Nix 2.4+ (flakes support)
- NixOS 23.05+
- Darwin (macOS) support
- Cross-platform model fetching

### 19.3 Documentation
- Comprehensive README
- API reference
- Common recipes and examples
- Troubleshooting guide

---

## 20. Dependencies

### 20.1 Runtime Dependencies

Required packages for the fetch/download phase:

| Package | Purpose | Required For |
|---------|---------|--------------|
| `curl` | HTTP/HTTPS downloads | All HTTP sources |
| `git` | Git repository access | Git LFS source |
| `git-lfs` | Large file storage | Git LFS source |
| `jq` | JSON parsing | Metadata extraction, HF API |
| `coreutils` | Basic utilities (sha256sum, etc.) | Hash verification |
| `cacert` | SSL certificates | HTTPS connections |

### 20.2 Optional Dependencies

```nix
{
  # For HuggingFace source (enhanced features)
  huggingface-cli = pkgs.python3Packages.huggingface-hub;  # Better HF integration

  # For cloud storage sources
  awscli2 = pkgs.awscli2;        # S3 source
  google-cloud-sdk = pkgs.google-cloud-sdk;  # GCS source
  azure-cli = pkgs.azure-cli;    # Azure Blob source

  # For security scanning (validation phase)
  modelscan = pkgs.python3Packages.modelscan;  # Model security scanner
  picklescan = pkgs.python3Packages.picklescan; # Pickle vulnerability scanner
  clamav = pkgs.clamav;          # General malware scanning

  # For model format conversion
  safetensors = pkgs.python3Packages.safetensors;
  pytorch = pkgs.python3Packages.torch;

  # For GGUF/Ollama support
  llama-cpp = pkgs.llama-cpp;
}
```

### 20.3 Build-time Dependencies

```nix
{
  buildInputs = [
    # Nix-specific
    pkgs.nix               # For nix-hash, nix-store operations

    # Standard build tools
    pkgs.stdenv.cc         # For any native compilation
    pkgs.makeWrapper       # For wrapper scripts
  ];

  nativeBuildInputs = [
    pkgs.installShellFiles  # For shell completions (CLI tool)
  ];
}
```

### 20.4 Dependency Matrix by Source

| Source | curl | git | git-lfs | awscli | huggingface-cli |
|--------|------|-----|---------|--------|-----------------|
| HuggingFace | ✓ | - | - | - | Optional |
| MLFlow | ✓ | - | - | - | - |
| Git LFS | - | ✓ | ✓ | - | - |
| HTTP/HTTPS | ✓ | - | - | - | - |
| S3 | - | - | - | ✓ | - |
| GCS | ✓ | - | - | - | - |
| Ollama | ✓ | - | - | - | - |

---

## 21. Testing Strategy

### 21.1 Test Categories

```
┌─────────────────────────────────────────────────────────────────────┐
│                         TEST PYRAMID                                 │
│                                                                      │
│                           ┌───────┐                                  │
│                           │  E2E  │  ← Real model downloads          │
│                          ─┴───────┴─                                 │
│                       ┌──────────────┐                               │
│                       │ Integration  │  ← Mock servers               │
│                      ─┴──────────────┴─                              │
│                   ┌─────────────────────┐                            │
│                   │     Unit Tests      │  ← Pure Nix functions      │
│                  ─┴─────────────────────┴─                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 21.2 Unit Tests

Test pure Nix functions without network access:

```nix
{
  # tests/unit/default.nix
  tests = {
    # Hash parsing and validation
    test_parseHash = {
      expr = lib.parseHash "sha256-abc123...";
      expected = { algo = "sha256"; hash = "abc123..."; };
    };

    # Source URL construction
    test_huggingfaceUrl = {
      expr = lib.mkHuggingFaceUrl {
        repo = "meta-llama/Llama-2-7b-hf";
        file = "config.json";
        revision = "main";
      };
      expected = "https://huggingface.co/meta-llama/Llama-2-7b-hf/resolve/main/config.json";
    };

    # Config validation
    test_validateConfig_missingHash = {
      expr = lib.validateConfig { source.huggingface.repo = "foo/bar"; };
      expected = { valid = false; errors = [ "hash is required" ]; };
    };

    # HuggingFace cache path generation
    test_hfCachePath = {
      expr = lib.mkHfCachePath "meta-llama" "Llama-2-7b-hf";
      expected = "models--meta-llama--Llama-2-7b-hf";
    };
  };
}
```

### 21.3 Integration Tests

Test against mock servers (no real model downloads):

```nix
{
  # tests/integration/default.nix

  # Mock HuggingFace server for testing
  mockHfServer = pkgs.writeShellScriptBin "mock-hf-server" ''
    ${pkgs.python3}/bin/python ${./mock-hf-server.py}
  '';

  tests = {
    # Test basic fetch with mock server
    test_fetchFromMockHf = pkgs.runCommand "test-fetch" {
      nativeBuildInputs = [ mockHfServer ];
    } ''
      # Start mock server
      mock-hf-server &
      SERVER_PID=$!

      # Run fetch against mock
      export HF_ENDPOINT="http://localhost:8080"
      result=$(nix build .#testModel --no-link --print-out-paths)

      # Verify output structure
      test -f "$result/config.json"
      test -f "$result/refs/main"

      kill $SERVER_PID
      touch $out
    '';

    # Test validation phase
    test_validationHooks = pkgs.runCommand "test-validation" {} ''
      # Test that validators are called correctly
      ...
    '';

    # Test rate limiting
    test_rateLimiting = pkgs.runCommand "test-rate-limit" {
      nativeBuildInputs = [ mockHfServer ];
    } ''
      # Verify rate limiting kicks in after threshold
      ...
    '';
  };
}
```

### 21.4 End-to-End Tests

Test with real (small) models - run in CI with caching:

```nix
{
  # tests/e2e/default.nix

  # Use small, public models for E2E tests
  testModels = {
    # ~500KB - tiny test model
    tinyModel = fetchModel {
      source.huggingface.repo = "hf-internal-testing/tiny-random-bert";
      hash = "sha256-...";
    };

    # ~50MB - small but realistic
    smallModel = fetchModel {
      source.huggingface.repo = "microsoft/DialoGPT-small";
      hash = "sha256-...";
    };
  };

  tests = {
    # Verify model can be loaded by transformers
    test_transformersLoad = pkgs.runCommand "test-load" {
      buildInputs = [ pkgs.python3Packages.transformers testModels.tinyModel ];
    } ''
      python -c "
        from transformers import AutoModel
        model = AutoModel.from_pretrained('${testModels.tinyModel}')
        print('Model loaded successfully')
      "
      touch $out
    '';

    # Verify HuggingFace cache symlinks work
    test_hfCacheIntegration = pkgs.runCommand "test-hf-cache" {
      buildInputs = [ pkgs.python3Packages.transformers ];
    } ''
      # Setup cache symlink
      mkdir -p $HOME/.cache/huggingface/hub
      ln -s ${testModels.tinyModel} $HOME/.cache/huggingface/hub/models--hf-internal-testing--tiny-random-bert

      # Load by name (not path)
      python -c "
        from transformers import AutoModel
        model = AutoModel.from_pretrained('hf-internal-testing/tiny-random-bert')
        print('Cache integration works')
      "
      touch $out
    '';

    # Test offline mode
    test_offlineMode = pkgs.runCommand "test-offline" {
      buildInputs = [ testModels.tinyModel ];
    } ''
      export HF_HUB_OFFLINE=1
      export TRANSFORMERS_OFFLINE=1

      python -c "
        from transformers import AutoModel
        model = AutoModel.from_pretrained('${testModels.tinyModel}')
      "
      touch $out
    '';
  };
}
```

### 21.5 Test Fixtures

```nix
{
  # tests/fixtures/default.nix

  fixtures = {
    # Minimal valid config.json for testing
    configJson = builtins.toJSON {
      model_type = "bert";
      architectures = [ "BertModel" ];
      hidden_size = 768;
    };

    # Fake model file (random bytes with correct structure)
    fakeModelFile = pkgs.runCommand "fake-model" {} ''
      dd if=/dev/urandom of=$out bs=1024 count=100
    '';

    # Mock HuggingFace API responses
    mockApiResponses = {
      modelInfo = builtins.toJSON {
        id = "test-org/test-model";
        sha = "abc123";
        siblings = [
          { rfilename = "config.json"; size = 500; }
          { rfilename = "model.safetensors"; size = 1000000; }
        ];
      };
    };
  };
}
```

### 21.6 CI/CD Test Configuration

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: cachix/install-nix-action@v24
      - run: nix flake check

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: cachix/install-nix-action@v24
      - run: nix build .#checks.x86_64-linux.integration

  e2e-tests:
    runs-on: ubuntu-latest
    # Only run on main branch (downloads real models)
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: cachix/install-nix-action@v24
      - uses: cachix/cachix-action@v12
        with:
          name: nix-ai-models
          authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
      - run: nix build .#checks.x86_64-linux.e2e
```

### 21.7 Test Coverage Requirements

| Component | Min Coverage | Critical Paths |
|-----------|--------------|----------------|
| Hash verification | 100% | All hash algos, mismatch detection |
| Source URL building | 100% | All source types |
| Config validation | 90% | Required fields, type checks |
| Rate limiting | 80% | Limit enforcement, backoff |
| Disk space checks | 80% | Pre-check, during-download abort |
| HF cache structure | 90% | Symlink creation, blob layout |
| Error handling | 90% | All error types, recovery |
| Validation hooks | 80% | Hook execution, failure modes |

---

## 22. Open Questions

1. **Authentication**: How to handle HuggingFace tokens, MLFlow credentials, S3 keys?
   - Options: Environment variables, Nix secrets, agenix integration

2. **Large model handling**: Models >100GB may need special treatment
   - Options: Streaming verification, chunked downloads, local mirrors

3. **Version pinning**: How to handle model versions that change without new commits?
   - Options: Content addressing, timestamp-based snapshots

4. **Offline mode**: How to handle air-gapped environments?
   - Options: Pre-fetch to local cache, vendored models

---

## 23. Success Criteria

- [ ] Can fetch models from HuggingFace Hub with hash verification
- [ ] Can run post-download security scans
- [ ] Models are properly cached in Nix store
- [ ] HuggingFace transformers can load models via symlinks
- [ ] Failure handling works as configured
- [ ] Works in flakes, NixOS modules, and dev shells
- [ ] Documentation covers all use cases
