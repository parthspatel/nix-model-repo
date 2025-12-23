# Nix AI Models

**Reproducible AI/ML Model Management for Nix**

Nix AI Models is a Nix library for fetching, validating, and managing AI/ML models
as reproducible Nix derivations. It supports multiple model sources including
HuggingFace Hub, MLFlow, S3, and more.

```nix
# Fetch a model from HuggingFace
llama = nix-ai-models.lib.fetchModel pkgs {
  name = "llama-2-7b";
  source.huggingface.repo = "meta-llama/Llama-2-7b-hf";
  hash = "sha256-...";
};
```

## Key Features

- **Reproducible**: Models are fetched as Fixed Output Derivations with hash verification
- **Secure**: Built-in security validators (modelscan, pickle scanning, safetensors enforcement)
- **Multi-Source**: Support for HuggingFace, MLFlow, S3, Git LFS, Git-Xet, and more
- **HuggingFace Integration**: Creates proper cache structure for seamless use with transformers
- **Flake-Native**: Designed for use in Nix flakes with NixOS and Home Manager modules

## Getting Started

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-ai-models.url = "github:your-org/nix-ai-models";
  };

  outputs = { nixpkgs, nix-ai-models, ... }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    fetchModel = nix-ai-models.lib.fetchModel pkgs;
  in {
    packages.x86_64-linux.my-model = fetchModel {
      name = "mistral-7b";
      source.huggingface.repo = "mistralai/Mistral-7B-v0.1";
      hash = "sha256-...";
    };
  };
}
```

## Documentation

```{toctree}
:maxdepth: 2
:caption: User Guide

getting-started
configuration
sources
validation
integration
examples
```

```{toctree}
:maxdepth: 2
:caption: Reference

api-reference
cli
modules
devenv
```

```{toctree}
:maxdepth: 1
:caption: Development

contributing
architecture
changelog
```

## Indices and tables

- {ref}`genindex`
- {ref}`search`
