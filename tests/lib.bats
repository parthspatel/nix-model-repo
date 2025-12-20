#!/usr/bin/env bats
# Tests for library functions

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "flake.nix exists" {
  [ -f "flake.nix" ]
}

@test "lib directory exists" {
  [ -d "lib" ]
}

@test "lib/default.nix exists" {
  [ -f "lib/default.nix" ]
}

@test "lib/fetchModel.nix exists" {
  [ -f "lib/fetchModel.nix" ]
}

@test "lib/types.nix exists" {
  [ -f "lib/types.nix" ]
}

@test "lib/sources/default.nix exists" {
  [ -f "lib/sources/default.nix" ]
}

@test "lib/validation/default.nix exists" {
  [ -f "lib/validation/default.nix" ]
}

@test "nix flake show succeeds" {
  if command -v nix &> /dev/null; then
    run nix flake show --json
    [ "$status" -eq 0 ]
  fi
}

@test "modelDefs evaluates" {
  if command -v nix &> /dev/null; then
    run nix eval .#modelDefs --json
    [ "$status" -eq 0 ]
  fi
}
