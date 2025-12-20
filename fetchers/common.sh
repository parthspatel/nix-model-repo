#!/usr/bin/env bash
# fetchers/common.sh - Shared utilities for all fetchers
# This file is sourced by individual fetcher scripts

set -euo pipefail

#
# LOGGING
#

log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

#
# ERROR HANDLING
#

# Structured error exit with helpful message
error_exit() {
    local source="$1"
    local error_type="$2"
    local message="$3"
    local help_url="${4:-}"

    cat >&2 << EOF

error: Failed to fetch model

  ┌─ Source: $source
  │
  ✗ Error: $error_type
  │
  │ $message
EOF

    if [[ -n "$help_url" ]]; then
        echo "  │" >&2
        echo "  └─ For more help: $help_url" >&2
    else
        echo "  └─" >&2
    fi
    echo "" >&2

    exit 1
}

# Handle HTTP errors with helpful messages
handle_http_error() {
    local code="$1"
    local url="$2"
    local source="${3:-unknown}"

    case "$code" in
        401)
            error_exit "$source" "HTTP 401 Unauthorized" \
                "Authentication required. Please set the appropriate token environment variable."
            ;;
        403)
            if [[ "$source" == "huggingface" ]]; then
                error_exit "$source" "HTTP 403 Forbidden" \
"This may be a gated model requiring license acceptance.

  To fix this:
    1. Visit the model page on HuggingFace
    2. Click 'Access repository' and accept the license
    3. Generate a token at https://huggingface.co/settings/tokens
    4. Set: export HF_TOKEN=your_token_here" \
                    "https://huggingface.co/settings/tokens"
            else
                error_exit "$source" "HTTP 403 Forbidden" \
                    "Access denied. Check your credentials and permissions."
            fi
            ;;
        404)
            error_exit "$source" "HTTP 404 Not Found" \
                "Resource not found: $url
Check the repository name, revision, and file paths."
            ;;
        429)
            log_warn "Rate limited (HTTP 429). Will retry with backoff."
            return 1
            ;;
        5*)
            error_exit "$source" "HTTP $code Server Error" \
                "The server is experiencing issues. Try again later."
            ;;
        *)
            error_exit "$source" "HTTP $code" \
                "Unexpected HTTP error when fetching: $url"
            ;;
    esac
}

#
# NETWORK UTILITIES
#

# Retry a command with exponential backoff
# Usage: retry_with_backoff 3 2 curl ...
retry_with_backoff() {
    local max_attempts="$1"
    local base_delay="$2"
    shift 2

    local attempt=1
    local delay="$base_delay"

    while true; do
        if "$@"; then
            return 0
        fi

        local exit_code=$?

        if [[ $attempt -ge $max_attempts ]]; then
            log_error "Command failed after $attempt attempts"
            return $exit_code
        fi

        log_warn "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"

        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}

# Download a file with progress and optional authentication
# Usage: download_file URL OUTPUT [TOKEN]
download_file() {
    local url="$1"
    local output="$2"
    local token="${3:-}"

    local curl_opts=(
        --fail
        --location
        --retry 3
        --retry-delay 2
        --connect-timeout "${CONNECT_TIMEOUT:-30}"
        --progress-bar
        --output "$output"
    )

    # Add max time if specified (0 = no limit)
    if [[ "${MAX_TIME:-0}" != "0" ]]; then
        curl_opts+=(--max-time "${MAX_TIME}")
    fi

    # Add bandwidth limit if specified
    if [[ -n "${BANDWIDTH_LIMIT:-}" ]]; then
        curl_opts+=(--limit-rate "$BANDWIDTH_LIMIT")
    fi

    # Add proxy if specified
    if [[ -n "${HTTP_PROXY:-}" ]]; then
        curl_opts+=(--proxy "$HTTP_PROXY")
    fi

    # Add authentication header if token provided
    if [[ -n "$token" ]]; then
        curl_opts+=(--header "Authorization: Bearer $token")
    fi

    log_debug "curl ${curl_opts[*]} $url"

    if ! curl "${curl_opts[@]}" "$url"; then
        local exit_code=$?
        # Try to get HTTP code for better error message
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [[ "$http_code" != "000" && "$http_code" != "200" ]]; then
            handle_http_error "$http_code" "$url" "${SOURCE_TYPE:-unknown}"
        fi
        return $exit_code
    fi
}

# Download with progress bar showing filename
download_with_progress() {
    local url="$1"
    local output="$2"
    local token="${3:-}"
    local filename="${4:-$(basename "$output")}"

    log_info "Downloading: $filename"
    download_file "$url" "$output" "$token"
}

#
# HUGGINGFACE CACHE STRUCTURE
#

# Create a blob in HuggingFace cache format
# The blob is named by its SHA256 hash
# Usage: create_hf_blob FILE BLOBS_DIR
# Returns: the blob hash
create_hf_blob() {
    local file="$1"
    local blobs_dir="$2"

    local sha256
    sha256=$(sha256sum "$file" | cut -d' ' -f1)

    mkdir -p "$blobs_dir"
    mv "$file" "$blobs_dir/$sha256"

    echo "$sha256"
}

# Create a symlink in the snapshots directory pointing to a blob
# Usage: create_hf_snapshot BLOBS_DIR SNAPSHOTS_DIR COMMIT_SHA FILENAME BLOB_HASH
create_hf_snapshot() {
    local blobs_dir="$1"
    local snapshots_dir="$2"
    local commit_sha="$3"
    local filename="$4"
    local blob_hash="$5"

    local snapshot_dir="$snapshots_dir/$commit_sha"

    # Handle nested paths in filename
    local file_dir
    file_dir=$(dirname "$filename")
    if [[ "$file_dir" != "." ]]; then
        mkdir -p "$snapshot_dir/$file_dir"
    else
        mkdir -p "$snapshot_dir"
    fi

    # Calculate relative path from snapshot to blobs
    # For nested files, we need more "../"
    local depth
    depth=$(echo "$filename" | tr -cd '/' | wc -c)
    local rel_prefix=".."
    for ((i=0; i<depth; i++)); do
        rel_prefix="../$rel_prefix"
    done

    # Create relative symlink: snapshots/<sha>/path/to/file → ../../../blobs/<hash>
    ln -sf "$rel_prefix/../blobs/$blob_hash" "$snapshot_dir/$filename"
}

# Create refs directory with main pointer
# Usage: create_hf_refs REFS_DIR COMMIT_SHA [REF_NAME]
create_hf_refs() {
    local refs_dir="$1"
    local commit_sha="$2"
    local ref_name="${3:-main}"

    mkdir -p "$refs_dir"
    echo "$commit_sha" > "$refs_dir/$ref_name"
}

#
# METADATA
#

# Write model metadata JSON
# Usage: write_metadata OUTPUT_DIR SOURCE FETCHED_AT [EXTRA_JSON]
write_metadata() {
    local output_dir="$1"
    local source="$2"
    local fetched_at="$3"
    local extra="${4:-}"

    local meta_file="$output_dir/.nix-ai-model-meta.json"

    if [[ -n "$extra" ]]; then
        cat > "$meta_file" << EOF
{
  "source": "$source",
  "fetchedAt": "$fetched_at",
  "nixAiModelVersion": "1.0.0",
  $extra
}
EOF
    else
        cat > "$meta_file" << EOF
{
  "source": "$source",
  "fetchedAt": "$fetched_at",
  "nixAiModelVersion": "1.0.0"
}
EOF
    fi
}

#
# FILE UTILITIES
#

# Check if a pattern matches a filename
# Usage: matches_pattern FILENAME PATTERN
matches_pattern() {
    local filename="$1"
    local pattern="$2"

    # Use bash's extended globbing
    shopt -s extglob nullglob

    # Convert glob to regex-ish matching
    # shellcheck disable=SC2053
    [[ "$filename" == $pattern ]]
}

# Filter a list of files by patterns
# Usage: filter_files FILES_ARRAY PATTERNS_ARRAY
# Reads from stdin, outputs matching files
filter_files() {
    local patterns="$1"

    if [[ -z "$patterns" ]]; then
        # No patterns = include all
        cat
        return
    fi

    while IFS= read -r file; do
        for pattern in $patterns; do
            if matches_pattern "$file" "$pattern"; then
                echo "$file"
                break
            fi
        done
    done
}

#
# DISK SPACE
#

# Check available disk space
# Usage: check_disk_space PATH MIN_BYTES
check_disk_space() {
    local path="$1"
    local min_bytes="$2"

    local available
    available=$(df --output=avail -B1 "$path" 2>/dev/null | tail -1)

    if [[ -n "$available" && "$available" -lt "$min_bytes" ]]; then
        local available_human
        local required_human
        available_human=$(numfmt --to=iec "$available" 2>/dev/null || echo "$available")
        required_human=$(numfmt --to=iec "$min_bytes" 2>/dev/null || echo "$min_bytes")
        error_exit "disk" "Insufficient disk space" \
            "Need $required_human but only $available_human available"
    fi
}

#
# JSON UTILITIES (using jq)
#

# Safely extract a JSON field
# Usage: json_get FILE PATH [DEFAULT]
json_get() {
    local file="$1"
    local path="$2"
    local default="${3:-}"

    local result
    result=$(jq -r "$path // empty" "$file" 2>/dev/null)

    if [[ -z "$result" ]]; then
        echo "$default"
    else
        echo "$result"
    fi
}
