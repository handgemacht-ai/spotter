#!/usr/bin/env bash
# Shared helper for generating W3C trace context headers.
# Provides trace_id and span_id generation utilities.
# Designed to fail gracefully - all functions return empty string on error.

# Generate N random bytes as lowercase hex.
# Prefers openssl; falls back to UUID conversion on Linux.
# Returns empty string if neither method works.
spotter_rand_hex() {
  local bytes="$1"

  # Try openssl first (fastest, most portable)
  if command -v openssl &> /dev/null; then
    openssl rand -hex "$bytes" 2>/dev/null && return 0
  fi

  # Fallback: use /proc on Linux (convert UUID format to hex)
  if [ -r /proc/sys/kernel/random/uuid ]; then
    # Read UUID and remove dashes, take first N*2 hex chars
    local uuid
    uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null)"
    if [ -n "$uuid" ]; then
      # Remove dashes and take N*2 characters
      local hex="${uuid//-/}"
      echo "${hex:0:$((bytes * 2))}"
      return 0
    fi
  fi

  # Could not generate random hex
  return 1
}

# Generate a W3C Trace Context compliant traceparent header value.
# Format: 00-<32 hex trace_id>-<16 hex span_id>-01
# Returns empty string if IDs cannot be generated (graceful failure).
spotter_generate_traceparent() {
  local trace_id span_id

  # Generate 16 bytes (32 hex chars) for trace_id
  trace_id="$(spotter_rand_hex 16)" || return 1

  # Generate 8 bytes (16 hex chars) for span_id
  span_id="$(spotter_rand_hex 8)" || return 1

  # Format as traceparent: version-trace_id-parent_id-trace_flags
  # Version=00, trace_flags=01 (sampled)
  echo "00-${trace_id}-${span_id}-01"
}
