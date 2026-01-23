#!/usr/bin/env bash
# fetchers/mlflow.sh - MLflow Model Registry fetcher
# This script is sourced after common.sh in the Nix build environment
#
# Required environment variables (set by Nix derivation):
#   TRACKING_URI  - MLflow tracking server URI (e.g., "https://mlflow.example.com")
#   MODEL_NAME    - Registered model name
#   out           - Nix output path
#
# One of these is required:
#   MODEL_VERSION - Specific version number
#   MODEL_STAGE   - Stage name (e.g., "Production", "Staging", "Archived")
#
# Optional environment variables:
#   MLFLOW_TRACKING_TOKEN  - Bearer token for authentication
#   MLFLOW_TRACKING_USERNAME - Basic auth username
#   MLFLOW_TRACKING_PASSWORD - Basic auth password
#   CONNECT_TIMEOUT - Connection timeout in seconds
#   MAX_TIME       - Maximum time for download in seconds

set -euo pipefail

# Validate required variables
: "${TRACKING_URI:?TRACKING_URI is required}"
: "${MODEL_NAME:?MODEL_NAME is required}"
: "${out:?out is required}"

# Optional variables with defaults
MODEL_VERSION="${MODEL_VERSION:-}"
MODEL_STAGE="${MODEL_STAGE:-}"
MLFLOW_TRACKING_TOKEN="${MLFLOW_TRACKING_TOKEN:-}"
MLFLOW_TRACKING_USERNAME="${MLFLOW_TRACKING_USERNAME:-}"
MLFLOW_TRACKING_PASSWORD="${MLFLOW_TRACKING_PASSWORD:-}"

# Validate that either version or stage is specified
if [[ -z $MODEL_VERSION && -z $MODEL_STAGE ]]; then
  error_exit "mlflow" "Missing version or stage" \
    "Either MODEL_VERSION or MODEL_STAGE must be specified"
fi

if [[ -n $MODEL_VERSION && -n $MODEL_STAGE ]]; then
  error_exit "mlflow" "Conflicting options" \
    "Specify either MODEL_VERSION or MODEL_STAGE, not both"
fi

log_info "Fetching MLflow model: $MODEL_NAME from $TRACKING_URI"
if [[ -n $MODEL_VERSION ]]; then
  log_info "  Version: $MODEL_VERSION"
else
  log_info "  Stage: $MODEL_STAGE"
fi

#
# API FUNCTIONS
#

# Build authentication headers for curl
get_auth_opts() {
  local auth_opts=()

  if [[ -n $MLFLOW_TRACKING_TOKEN ]]; then
    auth_opts+=(--header "Authorization: Bearer $MLFLOW_TRACKING_TOKEN")
  elif [[ -n $MLFLOW_TRACKING_USERNAME && -n $MLFLOW_TRACKING_PASSWORD ]]; then
    auth_opts+=(--user "$MLFLOW_TRACKING_USERNAME:$MLFLOW_TRACKING_PASSWORD")
  fi

  echo "${auth_opts[@]}"
}

# Make an authenticated API request to MLflow
mlflow_api_request() {
  local endpoint="$1"
  local method="${2:-GET}"
  local data="${3:-}"

  local curl_opts=(
    --silent
    --fail
    --location
    --connect-timeout "${CONNECT_TIMEOUT:-30}"
    --request "$method"
    --header "Content-Type: application/json"
  )

  # Add authentication
  if [[ -n $MLFLOW_TRACKING_TOKEN ]]; then
    curl_opts+=(--header "Authorization: Bearer $MLFLOW_TRACKING_TOKEN")
  elif [[ -n $MLFLOW_TRACKING_USERNAME && -n $MLFLOW_TRACKING_PASSWORD ]]; then
    curl_opts+=(--user "$MLFLOW_TRACKING_USERNAME:$MLFLOW_TRACKING_PASSWORD")
  fi

  if [[ -n $data ]]; then
    curl_opts+=(--data "$data")
  fi

  local url="${TRACKING_URI}${endpoint}"
  log_debug "MLflow API: $method $url"

  if ! curl "${curl_opts[@]}" "$url"; then
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${curl_opts[@]}" "$url" 2>/dev/null || echo "000")

    case "$http_code" in
    401)
      error_exit "mlflow" "HTTP 401 Unauthorized" \
        "Authentication required for MLflow server.

  To fix this, set one of:
    - MLFLOW_TRACKING_TOKEN for bearer token auth
    - MLFLOW_TRACKING_USERNAME and MLFLOW_TRACKING_PASSWORD for basic auth"
      ;;
    403)
      error_exit "mlflow" "HTTP 403 Forbidden" \
        "Access denied to MLflow server. Check your credentials and permissions."
      ;;
    404)
      error_exit "mlflow" "HTTP 404 Not Found" \
        "Model or endpoint not found: $url"
      ;;
    *)
      error_exit "mlflow" "HTTP $http_code" \
        "Failed to communicate with MLflow server: $url"
      ;;
    esac
  fi
}

# Get model version info from registry
get_model_version_info() {
  local name="$1"
  local version="${2:-}"
  local stage="${3:-}"

  local response

  if [[ -n $version ]]; then
    # Get specific version
    log_info "Getting model version $version..."
    response=$(mlflow_api_request "/api/2.0/mlflow/model-versions/get?name=$(urlencode "$name")&version=$version")
  else
    # Get latest version for stage
    log_info "Getting latest model version for stage '$stage'..."
    response=$(mlflow_api_request "/api/2.0/mlflow/registered-models/get?name=$(urlencode "$name")")

    # Filter to find the version with matching stage
    response=$(echo "$response" | jq --arg stage "$stage" '
            .registered_model.latest_versions[] |
            select(.current_stage == $stage) |
            {model_version: .}
        ')

    if [[ -z $response || $response == "null" ]]; then
      error_exit "mlflow" "No version found" \
        "No model version found with stage '$stage' for model '$name'"
    fi
  fi

  echo "$response"
}

# URL encode a string
urlencode() {
  local string="$1"
  python3 -c "import urllib.parse; print(urllib.parse.quote('$string', safe=''))"
}

# Download model artifacts from a run
download_model_artifacts() {
  local run_id="$1"
  local artifact_path="$2"
  local output_dir="$3"

  log_info "Downloading artifacts from run $run_id..."

  # List artifacts
  local artifacts_response
  artifacts_response=$(mlflow_api_request "/api/2.0/mlflow/artifacts/list?run_id=$run_id&path=$artifact_path")

  # Get the root artifact URI
  local root_uri
  root_uri=$(echo "$artifacts_response" | jq -r '.root_uri // empty')

  if [[ -z $root_uri ]]; then
    error_exit "mlflow" "No artifacts found" \
      "Could not find artifacts for run $run_id at path $artifact_path"
  fi

  # Download each file
  local files
  files=$(echo "$artifacts_response" | jq -r '.files[]? | select(.is_dir == false) | .path')

  if [[ -z $files ]]; then
    # Check for nested directories
    local dirs
    dirs=$(echo "$artifacts_response" | jq -r '.files[]? | select(.is_dir == true) | .path')

    for dir in $dirs; do
      download_model_artifacts "$run_id" "$dir" "$output_dir"
    done
    return
  fi

  local file_count
  file_count=$(echo "$files" | wc -l)
  log_info "Found $file_count files to download"

  local current=0
  echo "$files" | while IFS= read -r file_path; do
    [[ -z $file_path ]] && continue

    current=$((current + 1))

    # Determine relative path for output
    local rel_path="${file_path#"$artifact_path"/}"
    local output_file="$output_dir/$rel_path"

    mkdir -p "$(dirname "$output_file")"

    log_info "[$current/$file_count] Downloading: $rel_path"

    # Download via artifacts API
    local download_url="${TRACKING_URI}/api/2.0/mlflow/artifacts/download?run_id=$run_id&path=$file_path"

    local curl_opts=(
      --fail
      --location
      --connect-timeout "${CONNECT_TIMEOUT:-30}"
      --progress-bar
      --output "$output_file"
    )

    if [[ -n $MLFLOW_TRACKING_TOKEN ]]; then
      curl_opts+=(--header "Authorization: Bearer $MLFLOW_TRACKING_TOKEN")
    elif [[ -n $MLFLOW_TRACKING_USERNAME && -n $MLFLOW_TRACKING_PASSWORD ]]; then
      curl_opts+=(--user "$MLFLOW_TRACKING_USERNAME:$MLFLOW_TRACKING_PASSWORD")
    fi

    if ! curl "${curl_opts[@]}" "$download_url"; then
      # Try alternative download method (direct artifact store access)
      local direct_url="$root_uri/$rel_path"
      log_debug "Trying direct download from: $direct_url"

      if ! curl "${curl_opts[@]}" "$direct_url"; then
        error_exit "mlflow" "Download failed" \
          "Failed to download artifact: $rel_path"
      fi
    fi
  done
}

#
# MAIN EXECUTION
#

# Global temp_dir for cleanup trap
_MLFLOW_TEMP_DIR=""

_mlflow_cleanup() {
  if [[ -n ${_MLFLOW_TEMP_DIR:-} && -d $_MLFLOW_TEMP_DIR ]]; then
    rm -rf "$_MLFLOW_TEMP_DIR"
  fi
}

main() {
  # Create temporary directory
  _MLFLOW_TEMP_DIR=$(mktemp -d)
  trap _mlflow_cleanup EXIT

  local temp_dir="$_MLFLOW_TEMP_DIR"
  local model_dir="$temp_dir/model"
  mkdir -p "$model_dir"

  # Step 1: Get model version information
  local version_info
  version_info=$(get_model_version_info "$MODEL_NAME" "$MODEL_VERSION" "$MODEL_STAGE")

  # Extract key information
  local run_id source version current_stage
  run_id=$(echo "$version_info" | jq -r '.model_version.run_id')
  source=$(echo "$version_info" | jq -r '.model_version.source')
  version=$(echo "$version_info" | jq -r '.model_version.version')
  current_stage=$(echo "$version_info" | jq -r '.model_version.current_stage // "None"')

  log_info "Found model version:"
  log_info "  Version: $version"
  log_info "  Stage: $current_stage"
  log_info "  Run ID: $run_id"
  log_info "  Source: $source"

  # Step 2: Determine artifact path from source
  # Source is typically like "mlflow-artifacts:/0/abc123/artifacts/model"
  # or "s3://bucket/path/to/model"
  local artifact_path
  if [[ $source =~ mlflow-artifacts:/ ]]; then
    # Extract the path after "artifacts/"
    artifact_path=$(echo "$source" | sed -E 's|.*artifacts/||')
  elif [[ $source =~ ^runs:/ ]]; then
    # Format: runs:/<run_id>/<path>
    artifact_path=$(echo "$source" | sed -E 's|runs:/[^/]+/||')
  else
    # Assume it's a direct path
    artifact_path="model"
  fi

  log_info "Artifact path: $artifact_path"

  # Step 3: Download model artifacts
  download_model_artifacts "$run_id" "$artifact_path" "$model_dir"

  # Step 4: Write metadata
  write_metadata "$temp_dir" "mlflow:$TRACKING_URI/$MODEL_NAME@$version" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "\"trackingUri\": \"$TRACKING_URI\", \"modelName\": \"$MODEL_NAME\", \"version\": \"$version\", \"stage\": \"$current_stage\", \"runId\": \"$run_id\""

  # Step 5: Copy MLflow model metadata if present
  if [[ -f "$model_dir/MLmodel" ]]; then
    log_info "Found MLmodel metadata file"
  fi

  # Step 6: Move to output
  mkdir -p "$out"
  cp -r "$temp_dir"/* "$out"/

  # Count files
  local file_count
  file_count=$(find "$out" -type f | wc -l)

  log_info "Successfully fetched model to: $out"
  log_info "  Model: $MODEL_NAME"
  log_info "  Version: $version"
  log_info "  Stage: $current_stage"
  log_info "  Files: $file_count"

  # Clear the trap and clean up
  trap - EXIT
  _mlflow_cleanup
  _MLFLOW_TEMP_DIR=""
}

# Run main
main
