{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

{
  imports = [
    inputs.nix-model-repo.devenvModules.default
  ];

  services.model-repo = {
    enable = true;
    models = {
      llama = {
        source.huggingface = {
          repo = "meta-llama/Llama-3.1-8B-Instruct";
        };
        hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        auth.tokenEnvVar = "HF_TOKEN";
        auth.tokenFile = "/tmp/nix-model-repo-hf-token";
      };
    };
  };
}
