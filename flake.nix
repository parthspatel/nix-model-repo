{
  description = "Nix AI Model Manager - Reproducible AI/ML model management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    # Import our library
    mkLib = pkgs: import ./lib {
      inherit (nixpkgs) lib;
      inherit pkgs;
    };

  in {
    #
    # SYSTEM-AGNOSTIC EXPORTS
    #

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
    nixosModules.ai-models = self.nixosModules.default;

    # Home Manager module
    homeManagerModules.default = import ./modules/home-manager.nix;
    homeManagerModules.ai-models = self.homeManagerModules.default;

    # Overlay for pkgs integration
    overlays.default = final: _prev: {
      fetchAiModel = self.lib.fetchModel final;
      aiModelSources = self.lib.sources;
      aiModelValidation = self.lib.validation;
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
        # CLI tool will be added here
        # default = self.packages.${system}.nix-ai-model;
      }
    );

    # Development shell
    devShells = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages = [
            pkgs.jq
            pkgs.curl
            pkgs.shellcheck
          ];
        };
      }
    );

    # Checks (tests)
    checks = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib' = mkLib pkgs;
      in {
        # Type validation tests
        types = pkgs.runCommand "test-types" {} ''
          echo "Type tests would run here"
          touch $out
        '';
      }
    );
  };
}
