#!/usr/bin/env bats
# Tests for version management

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "VERSION file exists" {
  [ -f "VERSION" ]
}

@test "VERSION file contains valid semver" {
  version=$(cat VERSION | tr -d '[:space:]')
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]
}

@test "VERSION matches flake version" {
  file_version=$(cat VERSION | tr -d '[:space:]')
  # Skip if nix is not available
  if command -v nix &> /dev/null; then
    flake_version=$(nix eval --raw .#version 2>/dev/null || echo "skip")
    if [ "$flake_version" != "skip" ]; then
      [ "$file_version" = "$flake_version" ]
    fi
  fi
}
