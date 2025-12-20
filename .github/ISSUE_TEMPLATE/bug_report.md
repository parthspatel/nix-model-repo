---
name: Bug Report
about: Report a bug in nix-ai-models
title: '[BUG] '
labels: bug
assignees: ''
---

## Description

A clear description of the bug.

## To Reproduce

```nix
# Minimal example that reproduces the issue
fetchModel pkgs {
  name = "example";
  source.huggingface.repo = "org/model";
  hash = "sha256-...";
}
```

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened.

## Environment

- OS: [e.g., NixOS 24.05, Ubuntu 22.04]
- Nix version: [output of `nix --version`]
- nix-ai-models version: [e.g., 0.1.0 or commit hash]

## Additional Context

Any other relevant information.
