# lib/sources/mock.nix
# Mock source adapter for testing - creates empty model structure
{ lib, pkgs }:

{
  # Source type identifier
  sourceType = "mock";

  # Build a mock FOD derivation with empty files
  mkFetchDerivation =
    {
      name,
      hash,
      sourceConfig,
      auth ? { },
      network ? { },
    }:
    let
      # Mock config
      org = sourceConfig.org or "test-org";
      model = sourceConfig.model or "test-model";
      revision = sourceConfig.revision or "main";
      files = sourceConfig.files or [ "config.json" ];
      commitSha = sourceConfig.commitSha or "0000000000000000000000000000000000000000";

    in
    # Note: Mock source is NOT a fixed-output derivation since it doesn't fetch
    # from the network. The hash in the config is ignored for mock sources.
    # This is intentional - mock sources are for testing the pipeline, not
    # for reproducible network fetches.
    pkgs.stdenvNoCC.mkDerivation {
      name = "${name}-raw";

      dontUnpack = true;

      nativeBuildInputs = with pkgs; [
        coreutils
      ];

      buildPhase = ''
        runHook preBuild

        echo "Creating mock model structure for ${org}/${model}"

        # Create HuggingFace cache structure
        mkdir -p blobs snapshots/${commitSha} refs

        # Create ref
        echo "${commitSha}" > refs/main

        # Create mock files (skip config.json as it's handled specially)
        ${lib.concatMapStrings (file: ''
          ${lib.optionalString (file != "config.json") ''
            # Create empty blob content
            blob_content="mock content for ${file}"
            blob_hash=$(echo -n "$blob_content" | sha256sum | cut -d' ' -f1)
            echo -n "$blob_content" > "blobs/$blob_hash"

            # Create snapshot file (actual file, not symlink for simplicity)
            mkdir -p "snapshots/${commitSha}/$(dirname "${file}")"
            cp "blobs/$blob_hash" "snapshots/${commitSha}/${file}"
          ''}
        '') files}

        # Create minimal config.json if in files list
        ${
          if lib.elem "config.json" files then
            ''
              echo '{"model_type": "mock", "architectures": ["MockModel"]}' > config_tmp.json
              config_hash=$(sha256sum config_tmp.json | cut -d' ' -f1)
              mv config_tmp.json "blobs/$config_hash"
              cp "blobs/$config_hash" "snapshots/${commitSha}/config.json"
            ''
          else
            ""
        }

        # Write metadata
        cat > .nix-model-repo-meta.json << EOF
        {
          "source": "mock:${org}/${model}@${commitSha}",
          "fetchedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "nixModelRepoVersion": "1.0.0",
          "repository": "${org}/${model}",
          "commit": "${commitSha}",
          "org": "${org}",
          "model": "${model}",
          "mock": true
        }
        EOF

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r . $out/
        runHook postInstall
      '';

      passthru = {
        inherit org model revision;
        sourceType = "mock";
      };

      meta = {
        description = "Mock model: ${org}/${model}";
      };
    };

  # Validate mock source config
  validateConfig = sourceConfig: {
    valid = true;
    errors = [ ];
  };

  # No impure env vars needed
  impureEnvVars = _: [ ];

  # Minimal build inputs
  buildInputs =
    pkgs: with pkgs; [
      coreutils
      jq
    ];

  # Extract metadata
  extractMeta = sourceConfig: {
    org = sourceConfig.org or "test-org";
    model = sourceConfig.model or "test-model";
    revision = sourceConfig.revision or "main";
    sourceType = "mock";
    repo = "${sourceConfig.org or "test-org"}/${sourceConfig.model or "test-model"}";
  };
}
