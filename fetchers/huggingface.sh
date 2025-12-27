#!/usr/bin/env bash
# fetchers/huggingface.sh - HuggingFace Hub fetcher
# This script is sourced after common.sh in the Nix build environment
#
# Required environment variables (set by Nix derivation):
#   REPO     - HuggingFace repository (e.g., "meta-llama/Llama-2-7b-hf")
#   REVISION - Branch, tag, or commit SHA (e.g., "main")
#   out      - Nix output path
#
# Optional environment variables:
#   FILES          - Space-separated file patterns to download (empty = all)
#   HF_TOKEN       - HuggingFace API token for private/gated models
#   CONNECT_TIMEOUT - Connection timeout in seconds
#   MAX_TIME       - Maximum time for download in seconds
#   BANDWIDTH_LIMIT - Bandwidth limit (e.g., "1M")

set -euo pipefail

# Validate required variables
: "${REPO:?REPO is required}"
: "${REVISION:?REVISION is required}"
: "${out:?out is required}"

# Optional variables with defaults
FILES="${FILES:-}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"

# HuggingFace API endpoints
HF_API="https://huggingface.co/api"
HF_BASE="https://huggingface.co"

log_info "Fetching HuggingFace model: $REPO @ $REVISION"

#
# API FUNCTIONS
#

# Make an authenticated API request
hf_api_request() {
    local endpoint="$1"
    local curl_opts=(
        --silent
        --fail
        --location
        --connect-timeout "${CONNECT_TIMEOUT:-30}"
    )

    if [[ -n "$HF_TOKEN" ]]; then
        curl_opts+=(--header "Authorization: Bearer $HF_TOKEN")
    fi

    curl "${curl_opts[@]}" "$endpoint"
}

# Resolve a revision (branch/tag) to a commit SHA
resolve_revision() {
    local revision="$1"

    # If it looks like a full SHA (40 hex chars), use as-is
    if [[ "$revision" =~ ^[0-9a-f]{40}$ ]]; then
        echo "$revision"
        return
    fi

    log_info "Resolving revision: $revision"

    local api_url="$HF_API/models/$REPO/revision/$revision"
    local response

    if ! response=$(hf_api_request "$api_url" 2>&1); then
        if echo "$response" | grep -q "401\|403"; then
            if [[ -z "$HF_TOKEN" ]]; then
                error_exit "huggingface" "Authentication required" \
"This model requires authentication.

  To fix this:
    1. Create a token at https://huggingface.co/settings/tokens
    2. Set: export HF_TOKEN=your_token_here
    3. Retry the build" \
                    "https://huggingface.co/settings/tokens"
            else
                error_exit "huggingface" "Access denied" \
"Your token doesn't have access to this model.

  This might be a gated model. To fix this:
    1. Visit https://huggingface.co/$REPO
    2. Click 'Access repository' and accept the license
    3. Retry the build"
            fi
        else
            error_exit "huggingface" "Failed to resolve revision" \
                "Could not resolve revision '$revision' for $REPO. Check the repository and revision names."
        fi
    fi

    local sha
    sha=$(echo "$response" | jq -r '.sha // empty')

    if [[ -z "$sha" ]]; then
        error_exit "huggingface" "Invalid API response" \
            "Could not extract commit SHA from API response"
    fi

    log_info "Resolved to commit: $sha"
    echo "$sha"
}

# Get list of files in the repository at a specific commit
get_file_list() {
    local commit_sha="$1"

    log_info "Getting file list..."

    local api_url="$HF_API/models/$REPO/tree/$commit_sha"
    local response

    if ! response=$(hf_api_request "$api_url"); then
        error_exit "huggingface" "Failed to get file list" \
            "Could not retrieve file list from HuggingFace API"
    fi

    # Extract file paths (excluding directories)
    echo "$response" | jq -r '.[] | select(.type == "file") | .path'
}

# Filter files based on patterns
filter_file_list() {
    local patterns="$1"

    if [[ -z "$patterns" ]]; then
        # No patterns - include all files
        cat
        return
    fi

    log_info "Filtering files with patterns: $patterns"

    while IFS= read -r file; do
        for pattern in $patterns; do
            # Use bash glob matching
            # shellcheck disable=SC2053
            if [[ "$file" == $pattern ]]; then
                echo "$file"
                break
            fi
        done
    done
}

# Download a single file from HuggingFace
download_hf_file() {
    local commit_sha="$1"
    local filepath="$2"
    local output_file="$3"

    local url="$HF_BASE/$REPO/resolve/$commit_sha/$filepath"

    # Create parent directory if needed
    mkdir -p "$(dirname "$output_file")"

    download_with_progress "$url" "$output_file" "$HF_TOKEN" "$filepath"
}

#
# MAIN EXECUTION
#

main() {
    # Create temporary directory for downloads
    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    # Create HuggingFace cache structure directories
    local blobs_dir="$temp_dir/blobs"
    local snapshots_dir="$temp_dir/snapshots"
    local refs_dir="$temp_dir/refs"

    mkdir -p "$blobs_dir" "$snapshots_dir" "$refs_dir"

    # Step 1: Resolve revision to commit SHA
    local commit_sha
    commit_sha=$(resolve_revision "$REVISION")

    # Create snapshot directory for this commit
    mkdir -p "$snapshots_dir/$commit_sha"

    # Step 2: Get and filter file list
    local files
    files=$(get_file_list "$commit_sha" | filter_file_list "$FILES")

    if [[ -z "$files" ]]; then
        if [[ -n "$FILES" ]]; then
            error_exit "huggingface" "No files matched" \
                "No files matched the specified patterns: $FILES"
        else
            error_exit "huggingface" "Empty repository" \
                "No files found in repository $REPO at revision $REVISION"
        fi
    fi

    # Count files for progress
    local file_count
    file_count=$(echo "$files" | wc -l)
    log_info "Downloading $file_count files..."

    # Step 3: Download each file
    local current=0
    echo "$files" | while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue

        current=$((current + 1))
        log_info "[$current/$file_count] Downloading: $filepath"

        # Download to temp location
        local temp_file="$temp_dir/download_temp"
        download_hf_file "$commit_sha" "$filepath" "$temp_file"

        # Create blob (content-addressed storage)
        local blob_hash
        blob_hash=$(create_hf_blob "$temp_file" "$blobs_dir")

        # Create snapshot symlink
        create_hf_snapshot "$blobs_dir" "$snapshots_dir" "$commit_sha" "$filepath" "$blob_hash"

        log_debug "Stored: $filepath → blobs/$blob_hash"
    done

    # Step 4: Create refs
    create_hf_refs "$refs_dir" "$commit_sha" "main"

    # Also create ref for the original revision name if different
    if [[ "$REVISION" != "main" && "$REVISION" != "$commit_sha" ]]; then
        create_hf_refs "$refs_dir" "$commit_sha" "$REVISION"
    fi

    # Step 5: Write metadata
    local org model
    org=$(echo "$REPO" | cut -d'/' -f1)
    model=$(echo "$REPO" | cut -d'/' -f2)

    write_metadata "$temp_dir" "huggingface:$REPO@$commit_sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "\"repository\": \"$REPO\", \"commit\": \"$commit_sha\", \"org\": \"$org\", \"model\": \"$model\""

    # Step 6: Move to output
    mkdir -p "$out"
    cp -r "$temp_dir"/* "$out"/

    log_info "Successfully fetched model to: $out"
    log_info "  Repository: $REPO"
    log_info "  Commit: $commit_sha"
    log_info "  Files: $file_count"
}

# Run main
main
