# models/definitions.nix
# Model registry definitions
# Each model is a fetchModel configuration
{ lib }:

{
  # Test models using mock source
  test = {
    # Empty mock model for testing the pipeline
    empty = {
      name = "test-empty";
      source.mock = {
        org = "test-org";
        model = "empty-model";
        files = [ "config.json" ];
      };
      # This hash is for the empty mock model structure
      # To get the correct hash, build with a fake hash and Nix will tell you the real one
      hash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=";  # empty
    };

    # Mock model with minimal structure
    minimal = {
      name = "test-minimal";
      source.mock = {
        org = "test-org";
        model = "minimal-model";
        files = [ "config.json" "tokenizer.json" ];
      };
      hash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=";
    };
  };

  # Example real model definitions (hashes need to be filled in)
  # Uncomment and fill in hashes after testing
  #
  # meta-llama = {
  #   llama-2-7b = {
  #     name = "llama-2-7b";
  #     source.huggingface = {
  #       repo = "meta-llama/Llama-2-7b-hf";
  #     };
  #     hash = "sha256-...";
  #   };
  # };
  #
  # mistralai = {
  #   mistral-7b = {
  #     name = "mistral-7b";
  #     source.huggingface = {
  #       repo = "mistralai/Mistral-7B-v0.1";
  #     };
  #     hash = "sha256-...";
  #   };
  # };
  #
  # microsoft = {
  #   phi-2 = {
  #     name = "phi-2";
  #     source.huggingface = {
  #       repo = "microsoft/phi-2";
  #       files = [ "*.safetensors" "config.json" "tokenizer*" ];
  #     };
  #     hash = "sha256-...";
  #   };
  # };
}
