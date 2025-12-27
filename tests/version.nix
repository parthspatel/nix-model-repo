# tests/version.nix
# Unit tests for lib/version.nix
{ lib, pkgs }:

let
  version = import ../lib/version.nix { inherit lib; };

in {
  unitTests = {
    # Test: version string exists
    testVersionExists = {
      expr = version ? version;
      expected = true;
    };

    testVersionIsString = {
      expr = lib.isString version.version;
      expected = true;
    };

    # Test: version components
    testMajorExists = {
      expr = version ? major;
      expected = true;
    };

    testMinorExists = {
      expr = version ? minor;
      expected = true;
    };

    testPatchExists = {
      expr = version ? patch;
      expected = true;
    };

    testMajorIsInt = {
      expr = lib.isInt version.major;
      expected = true;
    };

    # Test: version tag
    testVersionTagExists = {
      expr = version ? versionTag;
      expected = true;
    };

    testVersionTagStartsWithV = {
      expr = lib.hasPrefix "v" version.versionTag;
      expected = true;
    };

    # Test: meta
    testMetaExists = {
      expr = version ? meta;
      expected = true;
    };

    testMetaHasVersion = {
      expr = version.meta ? version;
      expected = true;
    };

    # Test: compare function
    testCompareExists = {
      expr = lib.isFunction version.compare;
      expected = true;
    };

    testCompareSameVersion = {
      expr = version.compare version.version;
      expected = 0;
    };

    # Test: satisfies function
    testSatisfiesExists = {
      expr = lib.isFunction version.satisfies;
      expected = true;
    };
  };
}
