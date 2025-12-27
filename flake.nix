{
  description = "Nix Model Repo - Reproducible AI/ML model management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    # Version from VERSION file
    version = nixpkgs.lib.strings.trim (builtins.readFile ./VERSION);

    # Import our library
    mkLib = pkgs: import ./lib {
      inherit (nixpkgs) lib;
      inherit pkgs;
    };

    # Treefmt configuration for code formatting
    treefmtEval = system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
      projectRootFile = "flake.nix";
      programs.nixfmt-rfc-style.enable = true;
      programs.shfmt.enable = true;
      programs.prettier.enable = true;
      settings.formatter.prettier.includes = [ "*.md" "*.json" "*.yaml" "*.yml" ];
    };

  in {
    #
    # SYSTEM-AGNOSTIC EXPORTS
    #

    # Version info
    inherit version;

    # Core library - user passes pkgs explicitly
    lib = {
      # Main function: pkgs -> config -> derivation
      fetchModel = pkgs: (mkLib pkgs).fetchModel;

      # Source factories
      sources = import ./lib/sources/factories.nix { inherit (nixpkgs) lib; };

      # Validation presets and validators
      validation = {
        presets = import ./lib/validation/presets.nix { inherit (nixpkgs) lib; };
        validators = import ./lib/validation/validators.nix { inherit (nixpkgs) lib; };
      };

      # Version utilities
      version = import ./lib/version.nix { inherit (nixpkgs) lib; };

      # Instantiate model definitions with pkgs
      instantiate = pkgs: defs:
        nixpkgs.lib.mapAttrsRecursive
          (_path: def: (mkLib pkgs).fetchModel def)
          defs;

      # Create shell hook for HF cache setup
      mkShellHook = pkgs: config:
        (mkLib pkgs).mkShellHook config;
    };

    # Model definitions (system-agnostic configs, no derivations yet)
    modelDefs = import ./models/definitions.nix { inherit (nixpkgs) lib; };

    # NixOS module
    nixosModules.default = import ./modules/nixos.nix;
    nixosModules.model-repo = self.nixosModules.default;

    # Home Manager module
    homeManagerModules.default = import ./modules/home-manager.nix;
    homeManagerModules.model-repo = self.homeManagerModules.default;

    # Devenv module (for devenv.sh integration)
    devenvModules.default = import ./modules/devenv.nix;
    devenvModules.model-repo = self.devenvModules.default;

    # Overlay for pkgs integration
    overlays.default = final: _prev: {
      fetchModel = self.lib.fetchModel final;
      modelRepoSources = self.lib.sources;
      modelRepoValidation = self.lib.validation;
    };

  } // {
    #
    # PER-SYSTEM EXPORTS
    #

    # Pre-built models from registry (validated)
    models = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        self.lib.instantiate pkgs self.modelDefs
    );

    # Raw models (no validation, for CI/testing)
    rawModels = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        disableValidation = def: def // { validation.enable = false; };
      in
        self.lib.instantiate pkgs (
          nixpkgs.lib.mapAttrsRecursive (_: disableValidation) self.modelDefs
        )
    );

    # Packages (CLI tool, etc.)
    packages = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        # Documentation
        docs = pkgs.stdenvNoCC.mkDerivation {
          pname = "nix-model-repo-docs";
          inherit version;
          src = ./docs/sphinx;

          nativeBuildInputs = with pkgs.python3Packages; [
            sphinx
            furo
            myst-parser
            sphinx-copybutton
          ];

          buildPhase = ''
            runHook preBuild
            sphinx-build -b html . $out
            runHook postBuild
          '';

          dontInstall = true;
        };

        # CLI tool will be added here
        # default = self.packages.${system}.nix-model-repo;
      }
    );

    # Formatting
    formatter = forAllSystems (system:
      (treefmtEval system).config.build.wrapper
    );

    # Development shells
    devShells = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        treefmtBuild = (treefmtEval system).config.build;
      in {
        # Default development shell
        default = pkgs.mkShell {
          name = "nix-model-repo-dev";

          packages = with pkgs; [
            # Nix tools
            nix-prefetch
            nix-prefetch-git
            nixfmt-rfc-style
            nil  # Nix LSP

            # Shell tools
            shellcheck
            shfmt
            jq
            yq-go
            curl
            wget

            # Git
            git
            gh  # GitHub CLI

            # Documentation
            python3Packages.sphinx
            python3Packages.furo
            python3Packages.myst-parser
            python3Packages.sphinx-copybutton

            # Formatting
            treefmtBuild.wrapper
            nodePackages.prettier

            # CI tools
            actionlint  # GitHub Actions linter
            act  # Run GitHub Actions locally
          ];

          shellHook = ''
            echo "nix-model-repo development shell v${version}"
            echo ""
            echo "Available commands:"
            echo "  nix flake check       - Run all checks"
            echo "  nix build .#checks.x86_64-linux.unit-tests  - Run unit tests"
            echo "  nix build .#checks.x86_64-linux.integration - Run integration tests"
            echo "  nix fmt               - Format code"
            echo "  nix build .#docs      - Build documentation"
            echo "  actionlint            - Lint GitHub Actions"
            echo ""
          '';

          # Environment variables
          NIX_MODEL_REPO_VERSION = version;
        };

        # CI shell (minimal, for GitHub Actions)
        ci = pkgs.mkShell {
          name = "nix-model-repo-ci";

          packages = with pkgs; [
            nix-prefetch
            shellcheck
            shfmt
            jq
            treefmtBuild.wrapper
          ];

          NIX_MODEL_REPO_VERSION = version;
        };

        # Documentation shell
        docs = pkgs.mkShell {
          name = "nix-model-repo-docs";

          packages = with pkgs; [
            python3Packages.sphinx
            python3Packages.furo
            python3Packages.myst-parser
            python3Packages.sphinx-copybutton
            python3Packages.sphinx-autobuild
          ];

          shellHook = ''
            echo "Documentation development shell"
            echo ""
            echo "Commands:"
            echo "  cd docs/sphinx && sphinx-build -b html . _build/html"
            echo "  cd docs/sphinx && sphinx-autobuild . _build/html"
            echo ""
          '';
        };
      }
    );

    # Checks (tests)
    checks = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (nixpkgs) lib;

        # Import the test suite
        testSuite = import ./tests {
          inherit lib pkgs;
        };
      in {
        # Formatting check
        formatting = (treefmtEval system).config.build.check self;

        # Unit tests (pure Nix evaluation tests)
        unit-tests = testSuite.checks.unit-tests;

        # Integration tests
        integration = testSuite.checks.integration-tests;

        # All tests
        all-tests = testSuite.checks.all;

        # Shell script linting
        shellcheck = pkgs.runCommand "shellcheck" {
          nativeBuildInputs = [ pkgs.shellcheck ];
        } ''
          echo "Linting shell scripts..."
          find ${./fetchers} -name "*.sh" -exec shellcheck {} +
          touch $out
        '';

        # Build documentation
        docs = self.packages.${system}.docs;

        # Nix file evaluation smoke test
        eval = pkgs.runCommand "test-eval" {} ''
          echo "Testing Nix evaluation..."
          echo "Flake version: ${version}"
          echo "Model definitions: ${builtins.toJSON (lib.attrNames self.modelDefs)}"
          touch $out
        '';
      }
    );
  };
}
