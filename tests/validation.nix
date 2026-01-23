# tests/validation.nix
# Unit tests for lib/validation/
{ lib, pkgs }:

let
  # Import validation modules
  presets = import ../lib/validation/presets.nix { inherit lib; };
  validators = import ../lib/validation/validators.nix { inherit lib; };

in
{
  unitTests = {
    # Test: presets exist
    testPresetsStrict = {
      expr = presets ? strict;
      expected = true;
    };

    testPresetsStandard = {
      expr = presets ? standard;
      expected = true;
    };

    testPresetsMinimal = {
      expr = presets ? minimal;
      expected = true;
    };

    testPresetsNone = {
      expr = presets ? none;
      expected = true;
    };

    testPresetsParanoid = {
      expr = presets ? paranoid;
      expected = true;
    };

    # Test: preset structure
    testStrictHasEnable = {
      expr = presets.strict.enable;
      expected = true;
    };

    testNoneDisabled = {
      expr = presets.none.enable;
      expected = false;
    };

    testStrictHasValidators = {
      expr = lib.isList (presets.strict.validators or [ ]);
      expected = true;
    };

    # Test: validators exist
    testValidatorsNoPickleFiles = {
      expr = validators ? noPickleFiles;
      expected = true;
    };

    testValidatorsSafetensorsOnly = {
      expr = validators ? safetensorsOnly;
      expected = true;
    };

    testValidatorsMaxSize = {
      expr = lib.isFunction validators.maxSize;
      expected = true;
    };

    testValidatorsRequiredFiles = {
      expr = lib.isFunction validators.requiredFiles;
      expected = true;
    };

    # Test: validator structure
    testNoPickleFilesHasName = {
      expr = validators.noPickleFiles ? name;
      expected = true;
    };

    testNoPickleFilesHasCommand = {
      expr = validators.noPickleFiles ? command;
      expected = true;
    };

    # Test: parameterized validators
    testMaxSizeReturnsValidator = {
      expr = (validators.maxSize "10G") ? name;
      expected = true;
    };

    testMaxSizeNameContainsSize = {
      expr = lib.hasInfix "10G" (validators.maxSize "10G").name;
      expected = true;
    };

    testRequiredFilesReturnsValidator = {
      expr = (validators.requiredFiles [ "config.json" ]) ? name;
      expected = true;
    };
  };
}
