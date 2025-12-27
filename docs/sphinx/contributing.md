# Contributing

Thank you for your interest in contributing to Nix Model Repo!

## Getting Started

### Prerequisites

- Nix with flakes enabled
- Git

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-org/nix-model-repo.git
cd nix-model-repo

# Enter development shell
nix develop
```

## Project Structure

```
nix-model-repo/
├── flake.nix              # Main flake entry point
├── lib/
│   ├── default.nix        # Library exports
│   ├── fetchModel.nix     # Core fetch function
│   ├── types.nix          # Type definitions
│   ├── integration.nix    # HuggingFace integration
│   ├── sources/           # Source adapters
│   │   ├── default.nix    # Source dispatcher
│   │   ├── factories.nix  # Source factories
│   │   ├── huggingface.nix
│   │   ├── s3.nix
│   │   └── ...
│   └── validation/        # Validation framework
│       ├── default.nix
│       ├── presets.nix
│       └── validators.nix
├── fetchers/              # Shell scripts for fetching
│   ├── common.sh
│   └── huggingface.sh
├── models/                # Model registry
│   └── definitions.nix
├── modules/               # NixOS/Home Manager modules
│   ├── nixos.nix
│   └── home-manager.nix
└── docs/                  # Documentation
    └── sphinx/
```

## Development Workflow

### Making Changes

1. Create a feature branch:
   ```bash
   git checkout -b feature/my-feature
   ```

2. Make your changes

3. Test your changes:
   ```bash
   # Check flake evaluation
   nix flake check

   # Build test models
   nix build .#models.x86_64-linux.test.empty
   ```

4. Commit with a descriptive message:
   ```bash
   git commit -m "feat: add new feature"
   ```

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `refactor:` - Code refactoring
- `test:` - Test additions/changes
- `chore:` - Maintenance tasks

### Pull Requests

1. Push your branch:
   ```bash
   git push origin feature/my-feature
   ```

2. Open a pull request on GitHub

3. Ensure CI passes

4. Request review

## Adding a New Source Adapter

To add support for a new model source:

### 1. Create the Adapter

```nix
# lib/sources/mysource.nix
{ lib, pkgs }:

{
  sourceType = "mysource";

  mkFetchDerivation = {
    name,
    hash,
    sourceConfig,
    auth ? {},
    network ? {},
  }:
    pkgs.stdenvNoCC.mkDerivation {
      name = "${name}-raw";

      # FOD settings
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      outputHash = hash;

      # Your fetch logic
      buildPhase = ''
        # Download model files
      '';

      installPhase = ''
        mkdir -p $out
        cp -r . $out/
      '';
    };

  validateConfig = sourceConfig: {
    valid = /* validation logic */;
    errors = [];
  };

  impureEnvVars = auth: [
    # Environment variables needed during fetch
  ];

  buildInputs = pkgs: with pkgs; [
    # Build dependencies
  ];

  extractMeta = sourceConfig: {
    # Metadata extraction
  };
}
```

### 2. Register the Adapter

```nix
# lib/sources/default.nix
{
  adapters = {
    # ... existing adapters
    mysource = import ./mysource.nix { inherit lib pkgs; };
  };
}
```

### 3. Add Type Validation

```nix
# lib/types.nix
knownSourceTypes = [
  # ... existing types
  "mysource"
];
```

### 4. Create Factory (Optional)

```nix
# lib/sources/factories.nix
mkMysource = defaults: config: {
  mysource = defaults // config;
};
```

### 5. Add Documentation

Update `docs/sphinx/sources.md` with your new source type.

### 6. Add Tests

Create test model definitions using your source.

## Adding a New Validator

### 1. Create the Validator

```nix
# lib/validation/validators.nix
myValidator = mkValidator {
  name = "my-validator";
  description = "Description of what it validates";
  command = ''
    # Validation logic
    # $src contains the model path
    # Exit 0 for success, non-zero for failure
  '';
  # Optional
  timeout = 300;
  onFailure = "abort";
  buildInputs = [ pkgs.somePackage ];
};
```

### 2. Export the Validator

```nix
# lib/validation/validators.nix
{
  # ... existing validators
  myValidator = myValidator;
}
```

### 3. Add to Presets (if applicable)

```nix
# lib/validation/presets.nix
strict = {
  validators = [
    # ... existing
    validators.myValidator
  ];
};
```

### 4. Document the Validator

Update `docs/sphinx/validation.md`.

## Testing

### Running Tests

```bash
# Check flake
nix flake check

# Build all test models
nix build .#models.x86_64-linux.test.empty
nix build .#models.x86_64-linux.test.minimal

# Test specific functionality
nix eval .#lib.sources --apply 'x: builtins.attrNames x'
```

### Adding Test Models

```nix
# models/definitions.nix
{
  test = {
    myTest = {
      name = "test-my-feature";
      source.mock = {
        org = "test";
        model = "my-feature";
        files = [ "config.json" ];
      };
      hash = "sha256-...";
    };
  };
}
```

## Documentation

### Building Docs

```bash
cd docs/sphinx
nix-shell -p python3Packages.sphinx python3Packages.furo python3Packages.myst-parser
sphinx-build -b html . _build/html
```

### Documentation Style

- Use Markdown (`.md`) files
- Include code examples
- Keep explanations concise
- Use consistent formatting

## Code Style

### Nix

- Use `nixfmt` for formatting
- Prefer explicit imports over `with`
- Use descriptive variable names
- Add comments for complex logic

### Shell Scripts

- Use `shellcheck` for linting
- Use `set -euo pipefail`
- Quote variables
- Use functions for reusability

## Release Process

1. Update `CHANGELOG.md`
2. Update version in `flake.nix`
3. Create a git tag:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```
4. Create GitHub release

## Getting Help

- Open an issue for bugs or feature requests
- Start a discussion for questions
- Check existing issues before creating new ones

## License

By contributing, you agree that your contributions will be licensed under the project's license.
