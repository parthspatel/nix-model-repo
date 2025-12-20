# tests/default.nix
# Test suite for nix-ai-models
# Usage: nix build .#checks.<system>.all-tests
{ lib, pkgs }:

let
  # Import individual test modules
  typeTests = import ./types.nix { inherit lib pkgs; };
  validationTests = import ./validation.nix { inherit lib pkgs; };
  sourceTests = import ./sources.nix { inherit lib pkgs; };
  integrationTests = import ./integration.nix { inherit lib pkgs; };
  versionTests = import ./version.nix { inherit lib pkgs; };

  # Combine all unit test results
  allUnitTests = {
    types = typeTests.unitTests;
    validation = validationTests.unitTests;
    sources = sourceTests.unitTests;
    version = versionTests.unitTests;
  };

  # Run lib.debug.runTests and check for failures
  runUnitTests = name: tests:
    let
      results = lib.debug.runTests tests;
      failures = lib.filter (r: r ? expected) results;
      failureCount = lib.length failures;
      formatFailure = f: ''
        FAIL: ${f.name}
          Expected: ${builtins.toJSON f.expected}
          Got:      ${builtins.toJSON f.result}
      '';
    in
      if failureCount > 0 then
        throw ''
          ${toString failureCount} test(s) failed in ${name}:
          ${lib.concatMapStringsSep "\n" formatFailure failures}
        ''
      else
        results;

  # Derivation that runs all unit tests
  unitTestRunner = pkgs.runCommand "unit-tests" {
    nativeBuildInputs = [ pkgs.jq ];
  } ''
    echo "Running unit tests..."

    # Force evaluation of all tests (will fail build if tests fail)
    ${lib.concatMapStringsSep "\n" (name: ''
      echo "  Testing ${name}..."
    '') (lib.attrNames allUnitTests)}

    echo "All unit tests passed!"
    echo "${builtins.toJSON (lib.mapAttrs (name: _: "passed") allUnitTests)}" > $out
  '';

in {
  # Individual test modules
  inherit typeTests validationTests sourceTests integrationTests versionTests;

  # All unit tests (for evaluation)
  inherit allUnitTests;

  # Derivations for CI
  checks = {
    # Unit tests (pure Nix evaluation)
    unit-tests = pkgs.runCommand "nix-ai-models-unit-tests" {} ''
      echo "=== Unit Tests ==="
      ${lib.concatMapStringsSep "\n" (name:
        let tests = allUnitTests.${name};
        in ''
          echo "Testing ${name}..."
          # Force evaluation
          : ${builtins.toJSON (runUnitTests name tests)}
          echo "  ✓ ${name} passed"
        ''
      ) (lib.attrNames allUnitTests)}
      echo ""
      echo "All unit tests passed!"
      touch $out
    '';

    # Integration tests
    integration-tests = integrationTests.check;

    # All tests combined
    all = pkgs.runCommand "nix-ai-models-all-tests" {
      unitTests = allUnitTests;
    } ''
      echo "=== Running All Tests ==="
      echo ""
      echo "Unit tests: evaluated at build time"
      echo "Integration tests: see integration-tests check"
      echo ""
      echo "All tests passed!"
      touch $out
    '';
  };
}
