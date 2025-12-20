# CLI Reference

Nix AI Models includes command-line utilities for common operations.

```{note}
The CLI tools are currently planned for future implementation.
This documentation describes the intended interface.
```

## nix-ai-models

The main CLI tool for managing AI models.

### Installation

```bash
# Add to your flake
nix shell github:your-org/nix-ai-models

# Or install globally
nix profile install github:your-org/nix-ai-models
```

## Commands

### fetch

Fetch a model and add it to the Nix store.

```bash
nix-ai-models fetch [OPTIONS] <SOURCE>
```

**Arguments:**

- `SOURCE` - Model source in format `type:identifier` (e.g., `hf:meta-llama/Llama-2-7b-hf`)

**Options:**

| Option | Description |
|--------|-------------|
| `--name, -n` | Override derivation name |
| `--revision, -r` | Revision/version to fetch (default: main) |
| `--output, -o` | Output format: `path`, `json`, `link` (default: path) |
| `--link` | Create HuggingFace cache symlink after fetching |
| `--validation` | Validation preset: `strict`, `standard`, `minimal`, `none` |

**Examples:**

```bash
# Fetch from HuggingFace
nix-ai-models fetch hf:meta-llama/Llama-2-7b-hf

# Fetch specific revision
nix-ai-models fetch hf:meta-llama/Llama-2-7b-hf -r abc123

# Fetch and link to cache
nix-ai-models fetch hf:mistralai/Mistral-7B-v0.1 --link

# Fetch with minimal validation
nix-ai-models fetch hf:org/model --validation minimal
```

### hash

Compute or verify the hash of a model.

```bash
nix-ai-models hash [OPTIONS] <SOURCE>
```

**Options:**

| Option | Description |
|--------|-------------|
| `--verify` | Verify against provided hash instead of computing |
| `--format` | Output format: `sri`, `base32`, `base64` (default: sri) |

**Examples:**

```bash
# Compute hash for a model
nix-ai-models hash hf:google-bert/bert-base-uncased
# Output: sha256-abc123...

# Verify existing hash
nix-ai-models hash hf:org/model --verify sha256-abc123...
```

### link

Create HuggingFace cache symlinks for fetched models.

```bash
nix-ai-models link [OPTIONS] <MODEL_PATH>
```

**Options:**

| Option | Description |
|--------|-------------|
| `--cache-dir` | HuggingFace cache directory (default: `~/.cache/huggingface/hub`) |
| `--name` | Override the cache directory name |
| `--force, -f` | Overwrite existing links |

**Examples:**

```bash
# Link a built model
nix-ai-models link /nix/store/xxx-llama-2-7b

# Link with custom cache location
nix-ai-models link /nix/store/xxx-model --cache-dir /data/hf-cache

# Force overwrite
nix-ai-models link /nix/store/xxx-model -f
```

### list

List available or installed models.

```bash
nix-ai-models list [OPTIONS]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--installed` | List only installed models (in Nix store) |
| `--linked` | List only models linked to HF cache |
| `--format` | Output format: `table`, `json`, `paths` (default: table) |

**Examples:**

```bash
# List all defined models
nix-ai-models list

# List installed models as JSON
nix-ai-models list --installed --format json

# List linked models
nix-ai-models list --linked
```

### info

Show information about a model.

```bash
nix-ai-models info [OPTIONS] <MODEL>
```

**Options:**

| Option | Description |
|--------|-------------|
| `--format` | Output format: `text`, `json` (default: text) |

**Examples:**

```bash
# Show model info
nix-ai-models info hf:meta-llama/Llama-2-7b-hf

# JSON output
nix-ai-models info hf:org/model --format json
```

### validate

Run validation on an existing model.

```bash
nix-ai-models validate [OPTIONS] <MODEL_PATH>
```

**Options:**

| Option | Description |
|--------|-------------|
| `--preset` | Validation preset to use |
| `--validator` | Specific validator to run (can be repeated) |
| `--continue-on-error` | Continue validation even if a check fails |

**Examples:**

```bash
# Validate with default settings
nix-ai-models validate /nix/store/xxx-model

# Use strict validation
nix-ai-models validate /nix/store/xxx-model --preset strict

# Run specific validators
nix-ai-models validate /path --validator no-pickle --validator max-size:10G
```

### clean

Clean up unused models and cache.

```bash
nix-ai-models clean [OPTIONS]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be removed without removing |
| `--broken-links` | Only remove broken symlinks from HF cache |

**Examples:**

```bash
# Clean broken links
nix-ai-models clean --broken-links

# Dry run
nix-ai-models clean --dry-run
```

## Using with Nix Commands

You can also use standard Nix commands with the flake:

### Build a Model

```bash
# Build a pre-defined model
nix build github:your-org/nix-ai-models#models.x86_64-linux.test.empty

# Build with local flake
nix build .#llama-2-7b
```

### Evaluate Model Configuration

```bash
# Show model derivation
nix eval .#llama-2-7b --apply 'd: d.drvPath'

# Show model metadata
nix eval .#llama-2-7b.passthru.meta --json
```

### Development Shell

```bash
# Enter dev shell with models available
nix develop .#default

# Or with specific model
nix develop .#with-llama
```

## Environment Variables

The CLI respects these environment variables:

| Variable | Description |
|----------|-------------|
| `HF_TOKEN` | HuggingFace authentication token |
| `HF_HOME` | HuggingFace cache directory (default: `~/.cache/huggingface`) |
| `NIX_AI_MODELS_CACHE` | Cache directory for CLI operations |
| `NIX_AI_MODELS_VALIDATION` | Default validation preset |

## Shell Completions

Generate shell completions:

```bash
# Bash
nix-ai-models completions bash > ~/.local/share/bash-completion/completions/nix-ai-models

# Zsh
nix-ai-models completions zsh > ~/.zsh/completions/_nix-ai-models

# Fish
nix-ai-models completions fish > ~/.config/fish/completions/nix-ai-models.fish
```
