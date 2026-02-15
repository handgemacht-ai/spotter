#!/usr/bin/env bash
# Shared helper for hook HTTP POST calls with explicit failure tracing to stderr.

# spotter_post_hook_json <base_url> <path> <body> <event> <script> <traceparent> <connect_timeout> <max_time>
# Returns 0 on successful 2xx response, 1 otherwise.
spotter_post_hook_json() {
  local base_url="$1"
  local path="$2"
  local body="$3"
  local event_name="$4"
  local script_name="$5"
  local traceparent="${6:-}"
  local connect_timeout="${7:-0.1}"
  local max_time="${8:-0.3}"

  local url
  local curl_tmp
  local http_code
  local curl_rc
  local curl_err

  url="${base_url%/}/${path#/}"
  curl_tmp="$(mktemp /tmp/spotter-hook-curl.XXXXXX)"

  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "x-spotter-hook-event: ${event_name}" \
    -H "x-spotter-hook-script: ${script_name}" \
    ${traceparent:+-H "traceparent: ${traceparent}"} \
    --connect-timeout "${connect_timeout}" \
    --max-time "${max_time}" \
    -d "$body" \
    2>"$curl_tmp")"
  curl_rc=$?

  curl_err="$(cat "$curl_tmp" 2>/dev/null | tr -d '\n' || true)"
  rm -f "$curl_tmp"

  if [ "$curl_rc" -ne 0 ] || ! [[ "$http_code" == 2[0-9][0-9] ]]; then
    echo "[spotter-hook] event=${event_name} script=${script_name} url=${url} status=${http_code:-n/a} curl_rc=${curl_rc} err=${curl_err:-n/a}" >&2
    return 1
  fi

  return 0
}

