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
    pkgs.stdenvNoCC.mkDerivation {
      name = "${name}-raw";

      # Fixed-output derivation settings
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      outputHash = hash;

      dontUnpack = true;

      nativeBuildInputs = with pkgs; [
        coreutils
        jq
      ];

      buildPhase = ''
        runHook preBuild

        echo "Creating mock model structure for ${org}/${model}"

        # Create HuggingFace cache structure
        mkdir -p blobs snapshots/${commitSha} refs

        # Create ref
        echo "${commitSha}" > refs/main

        # Create mock files
        ${lib.concatMapStrings (file: ''
          # Create empty blob
          touch "blobs/empty_${builtins.hashString "sha256" file}"

          # Create snapshot symlink
          mkdir -p "snapshots/${commitSha}/$(dirname "${file}")"
          ln -s "../../blobs/empty_${builtins.hashString "sha256" file}" "snapshots/${commitSha}/${file}"
        '') files}

        # Create minimal config.json if in files list
        ${
          if lib.elem "config.json" files then
            ''
              echo '{"model_type": "mock", "architectures": ["MockModel"]}' > snapshots/${commitSha}/config.json
              config_hash=$(sha256sum snapshots/${commitSha}/config.json | cut -d' ' -f1)
              mv snapshots/${commitSha}/config.json blobs/$config_hash
              ln -sf "../../blobs/$config_hash" snapshots/${commitSha}/config.json
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
