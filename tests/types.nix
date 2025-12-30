# tests/types.nix
# Unit tests for lib/types.nix
{ lib, pkgs }:

let
  # Import the types module
  types = import ../lib/types.nix { inherit lib; };

in
{
  # Unit tests using lib.debug.runTests format
  # Each test has: name, expr (actual), expected
  unitTests = {
    # Test: known source types list
    testKnownSourceTypesExists = {
      expr = lib.isList types.knownSourceTypes;
      expected = true;
    };

    testKnownSourceTypesContainsHuggingface = {
      expr = lib.elem "huggingface" types.knownSourceTypes;
      expected = true;
    };

    testKnownSourceTypesContainsMock = {
      expr = lib.elem "mock" types.knownSourceTypes;
      expected = true;
    };

    testKnownSourceTypesContainsS3 = {
      expr = lib.elem "s3" types.knownSourceTypes;
      expected = true;
    };

    # Test: source validation
    testValidateSourceHuggingface = {
      expr =
        (types.validateSource {
          huggingface = {
            repo = "org/model";
          };
        }).valid;
      expected = true;
    };

    testValidateSourceMock = {
      expr =
        (types.validateSource {
          mock = {
            org = "test";
            model = "test";
          };
        }).valid;
      expected = true;
    };

    testValidateSourceEmpty = {
      expr = (types.validateSource { }).valid;
      expected = false;
    };

    testValidateSourceMultiple = {
      expr =
        (types.validateSource {
          huggingface = { };
          s3 = { };
        }).valid;
      expected = false;
    };

    # Test: hash normalization
    testNormalizeHashSri = {
      expr = types.normalizeHash "sha256-abc123";
      expected = "sha256-abc123";
    };

    testNormalizeHashHex = {
      # 64-char hex string gets normalized to SRI format with sha256- prefix
      expr = lib.hasPrefix "sha256-" (
        types.normalizeHash "0000000000000000000000000000000000000000000000000000000000000000"
      );
      expected = true;
    };

    # Test: config validation
    testValidateConfigMinimal = {
      expr =
        (types.validateConfig {
          name = "test";
          source.mock = { };
          hash = "sha256-test";
        }).valid;
      expected = true;
    };

    testValidateConfigMissingName = {
      expr =
        (types.validateConfig {
          source.mock = { };
          hash = "sha256-test";
        }).valid;
      expected = false;
    };

    testValidateConfigMissingHash = {
      expr =
        (types.validateConfig {
          name = "test";
          source.mock = { };
        }).valid;
      expected = false;
    };

    # Test: default merging
    testMergeWithDefaultsAddsValidation = {
      expr =
        (types.mergeWithDefaults {
          name = "test";
          source.mock = { };
          hash = "sha256-test";
        }) ? validation;
      expected = true;
    };

    testMergeWithDefaultsPreservesName = {
      expr =
        (types.mergeWithDefaults {
          name = "my-model";
          source.mock = { };
          hash = "sha256-test";
        }).name;
      expected = "my-model";
    };
  };
}
