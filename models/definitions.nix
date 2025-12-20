# models/definitions.nix
# Model registry definitions
# Each model is a fetchModel configuration (without the hash initially)
{ lib }:

{
  # Example models will be added here as they are tested
  # Format:
  # <org>.<model-name> = {
  #   name = "model-name";
  #   source.<type> = { ... };
  #   hash = "sha256-...";
  # };

  # Placeholder for testing
  # meta-llama.llama-2-7b = {
  #   name = "llama-2-7b";
  #   source.huggingface = {
  #     repo = "meta-llama/Llama-2-7b-hf";
  #   };
  #   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  # };
}
