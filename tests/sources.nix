# tests/sources.nix
# Unit tests for lib/sources/
{ lib, pkgs }:

let
  # Import source modules
  factories = import ../lib/sources/factories.nix { inherit lib; };

  # Mock source for testing
  mockSource = import ../lib/sources/mock.nix { inherit lib pkgs; };

in
{
  unitTests = {
    # Test: factories exist
    testHuggingFaceExists = {
      expr = factories ? huggingface;
      expected = true;
    };

    testHuggingFaceMkExists = {
      expr = factories.huggingface ? mk;
      expected = true;
    };

    testMkS3Exists = {
      expr = factories ? mkS3;
      expected = true;
    };

    testMkMlflowExists = {
      expr = factories ? mkMlflow;
      expected = true;
    };

    testMkGitLfsExists = {
      expr = factories ? mkGitLfs;
      expected = true;
    };

    # Test: factories are functions
    testHuggingFaceMkIsFunction = {
      expr = lib.isFunction factories.huggingface.mk;
      expected = true;
    };

    testMkS3IsFunction = {
      expr = lib.isFunction factories.mkS3;
      expected = true;
    };

    # Test: mock source adapter
    testMockSourceType = {
      expr = mockSource.sourceType;
      expected = "mock";
    };

    testMockHasMkFetchDerivation = {
      expr = mockSource ? mkFetchDerivation;
      expected = true;
    };

    testMockHasValidateConfig = {
      expr = mockSource ? validateConfig;
      expected = true;
    };

    testMockValidateConfigEmpty = {
      expr = (mockSource.validateConfig { }).valid;
      expected = true;
    };

    testMockValidateConfigWithFiles = {
      expr = (mockSource.validateConfig { files = [ "config.json" ]; }).valid;
      expected = true;
    };

    # Test: factory produces valid source config
    testHuggingFaceMkProducesConfig = {
      expr =
        let
          config = factories.huggingface.mk { repo = "org/model"; };
        in
        config ? huggingface;
      expected = true;
    };

    testHuggingFaceMkConfigHasRepo = {
      expr =
        let
          config = factories.huggingface.mk { repo = "org/model"; };
        in
        config.huggingface.repo;
      expected = "org/model";
    };

    testHuggingFaceOrgFactory = {
      expr =
        let
          config = factories.huggingface.org "myorg" "mymodel";
        in
        config.huggingface.repo;
      expected = "myorg/mymodel";
    };

    testMkS3ProducesConfig = {
      expr =
        let
          s3 = factories.mkS3 {
            bucket = "test-bucket";
            region = "us-east-1";
          };
          config = s3 { prefix = "models/"; };
        in
        config ? s3;
      expected = true;
    };

    testMkS3ConfigHasBucket = {
      expr =
        let
          s3 = factories.mkS3 {
            bucket = "test-bucket";
            region = "us-east-1";
          };
          config = s3 { prefix = "models/"; };
        in
        config.s3.bucket;
      expected = "test-bucket";
    };
  };
}
