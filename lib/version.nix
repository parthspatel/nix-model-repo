# lib/version.nix
# Version management utilities
{ lib }:

let
  # Read version from VERSION file
  versionFile = builtins.readFile ../VERSION;
  version = lib.strings.trim versionFile;

  # Parse semver components
  versionParts = lib.strings.splitString "." version;
  major = lib.toInt (builtins.elemAt versionParts 0);
  minor = lib.toInt (builtins.elemAt versionParts 1);
  patch = lib.toInt (builtins.elemAt versionParts 2);

in {
  # Full version string
  inherit version;

  # Semver components
  inherit major minor patch;

  # Version with 'v' prefix (for git tags)
  versionTag = "v${version}";

  # Check if version satisfies constraint
  # e.g., satisfies ">=0.1.0" returns true for 0.1.0, 0.2.0, etc.
  satisfies = constraint:
    let
      # Parse constraint like ">=0.1.0" or "^0.1.0"
      op = builtins.substring 0 2 constraint;
      constraintVersion = builtins.substring 2 (-1) constraint;
      cParts = lib.strings.splitString "." constraintVersion;
      cMajor = lib.toInt (builtins.elemAt cParts 0);
      cMinor = lib.toInt (builtins.elemAt cParts 1);
      cPatch = lib.toInt (builtins.elemAt cParts 2);
    in
      if op == ">=" then
        major > cMajor ||
        (major == cMajor && minor > cMinor) ||
        (major == cMajor && minor == cMinor && patch >= cPatch)
      else if op == "==" then
        major == cMajor && minor == cMinor && patch == cPatch
      else
        throw "Unsupported version constraint operator: ${op}";

  # Compare versions: -1 (less), 0 (equal), 1 (greater)
  compare = other:
    let
      oParts = lib.strings.splitString "." other;
      oMajor = lib.toInt (builtins.elemAt oParts 0);
      oMinor = lib.toInt (builtins.elemAt oParts 1);
      oPatch = lib.toInt (builtins.elemAt oParts 2);
    in
      if major != oMajor then (if major > oMajor then 1 else -1)
      else if minor != oMinor then (if minor > oMinor then 1 else -1)
      else if patch != oPatch then (if patch > oPatch then 1 else -1)
      else 0;

  # Metadata for derivations
  meta = {
    inherit version;
    homepage = "https://github.com/your-org/nix-model-repo";
    changelog = "https://github.com/your-org/nix-model-repo/blob/main/CHANGELOG.md";
  };
}
