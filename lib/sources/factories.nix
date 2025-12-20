# lib/sources/factories.nix
# Source factory functions for creating source configurations
{ lib }:

{
  #
  # HUGGINGFACE FACTORIES
  #

  huggingface = {
    # Pre-configured for major organizations
    metaLlama = model: {
      huggingface = {
        repo = "meta-llama/${model}";
      };
    };

    mistralai = model: {
      huggingface = {
        repo = "mistralai/${model}";
      };
    };

    microsoft = model: {
      huggingface = {
        repo = "microsoft/${model}";
      };
    };

    google = model: {
      huggingface = {
        repo = "google/${model}";
      };
    };

    openai = model: {
      huggingface = {
        repo = "openai/${model}";
      };
    };

    # Generic organization factory
    org = orgName: model: {
      huggingface = {
        repo = "${orgName}/${model}";
      };
    };

    # Full factory with all options
    mk = { repo, revision ? "main", files ? null }: {
      huggingface = {
        inherit repo revision;
      } // lib.optionalAttrs (files != null) { inherit files; };
    };
  };

  #
  # OLLAMA FACTORY
  #

  ollama = {
    model = name: {
      ollama = {
        inherit (builtins.parseDrvName name) name;
        model = name;
      };
    };
  };

  #
  # CUSTOM FACTORY BUILDERS
  #

  # Create an MLFlow source factory for a specific tracking server
  # Usage: mkMlflow { trackingUri = "https://mlflow.example.com"; }
  # Returns: { modelName, version?, stage? } -> sourceConfig
  mkMlflow = { trackingUri }: { modelName, version ? null, stage ? null }: {
    mlflow = {
      inherit trackingUri modelName;
      modelVersion = version;
      modelStage = stage;
    };
  };

  # Create an S3 source factory for a specific bucket
  # Usage: mkS3 { bucket = "my-models"; region = "us-west-2"; }
  # Returns: { prefix, files? } -> sourceConfig
  mkS3 = { bucket, region }: { prefix, files ? null }: {
    s3 = {
      inherit bucket region prefix;
    } // lib.optionalAttrs (files != null) { inherit files; };
  };

  # Create a Git LFS source factory for a base URL
  # Usage: mkGitLfs { baseUrl = "https://github.com/myorg"; }
  # Returns: { repo, rev, files? } -> sourceConfig
  mkGitLfs = { baseUrl }: { repo, rev, files ? null }: {
    git-lfs = {
      url = "${baseUrl}/${repo}.git";
      inherit rev;
      lfsFiles = files;
    };
  };

  # Create a Git-Xet source factory for an endpoint
  # Usage: mkGitXet { endpoint = "https://xethub.example.com"; }
  # Returns: { url, rev, files? } -> sourceConfig
  mkGitXet = { endpoint }: { url, rev, files ? null }: {
    git-xet = {
      inherit url rev;
      xet = { inherit endpoint; };
    } // lib.optionalAttrs (files != null) { inherit files; };
  };

  # Create an HTTP source factory for a base URL
  # Usage: mkHttp { baseUrl = "https://models.example.com"; }
  # Returns: { path, filename? } -> sourceConfig
  mkHttp = { baseUrl }: { path, filename ? null }: {
    url = {
      urls = [{
        url = "${baseUrl}/${path}";
      } // lib.optionalAttrs (filename != null) { inherit filename; }];
    };
  };
}
