# lib/validation/presets.nix
# Validation presets for common use cases
{ lib }:

let
  validators = import ./validators.nix { inherit lib; };

in {
  #
  # STRICT PRESET
  # For production deployments - maximum security
  #
  strict = {
    enable = true;
    skipDefaults = false;
    defaults = {
      modelscan = true;
      pickleScan = true;
      checksums = true;
    };
    validators = [
      validators.noPickleFiles
      validators.safetensorsOnly
      validators.noPythonCode
      validators.validConfigJson
      validators.licenseCheck
      validators.validHfStructure
    ];
    onFailure = "abort";
    timeout = 600;  # 10 minutes for large models
  };

  #
  # STANDARD PRESET
  # Default for most use cases - good security without being too strict
  #
  standard = {
    enable = true;
    skipDefaults = false;
    defaults = {
      modelscan = true;
      pickleScan = true;
      checksums = true;
    };
    validators = [
      validators.validConfigJson
      validators.validHfStructure
    ];
    onFailure = "abort";
    timeout = 300;
  };

  #
  # MINIMAL PRESET
  # For CI/testing - faster builds with basic integrity checks
  #
  minimal = {
    enable = true;
    skipDefaults = true;  # Skip slow security scans
    defaults = {
      modelscan = false;
      pickleScan = false;
      checksums = true;  # Always verify integrity
    };
    validators = [
      validators.validHfStructure
    ];
    onFailure = "warn";  # Don't fail builds for validation issues
    timeout = 60;
  };

  #
  # NONE PRESET
  # Skip all validation - raw data only
  #
  none = {
    enable = false;
    skipDefaults = true;
    defaults = {
      modelscan = false;
      pickleScan = false;
      checksums = false;
    };
    validators = [];
    onFailure = "skip";
    timeout = 0;
  };

  #
  # PARANOID PRESET
  # Maximum security for sensitive deployments
  #
  paranoid = {
    enable = true;
    skipDefaults = false;
    defaults = {
      modelscan = true;
      pickleScan = true;
      checksums = true;
    };
    validators = [
      validators.noPickleFiles
      validators.safetensorsOnly
      validators.noPythonCode
      (validators.maxSize "100G")
      validators.validConfigJson
      validators.licenseCheck
      validators.signatureVerify
      validators.validHfStructure
      (validators.requiredFiles [ "config.json" ])
    ];
    onFailure = "abort";
    timeout = 1200;  # 20 minutes
  };

  #
  # QUICK PRESET
  # Fast validation for development - just basic structure
  #
  quick = {
    enable = true;
    skipDefaults = true;
    defaults = {
      modelscan = false;
      pickleScan = false;
      checksums = false;
    };
    validators = [
      validators.validHfStructure
    ];
    onFailure = "warn";
    timeout = 30;
  };
}
