#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

SOURCE_ROOT="${1:-${HOME}/.claude/projects}"
DEST_ROOT="${2:-${REPO_ROOT}/test/fixtures/transcripts}"
MAX_FILES="${MAX_FILES:-6}"

readonly SPOTTER_DIR_PATTERN='^-home-[^/]+-projects-spotter$'
readonly SPOTTER_WORKTREES_PATTERN='^-home-[^/]+-projects-spotter-worktrees($|-)'

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

if [[ ! -d "${SOURCE_ROOT}" ]]; then
  echo "source directory not found: ${SOURCE_ROOT}" >&2
  exit 1
fi

if ! [[ "${MAX_FILES}" =~ ^[0-9]+$ ]] || [[ "${MAX_FILES}" -lt 1 ]]; then
  echo "MAX_FILES must be a positive integer, got: ${MAX_FILES}" >&2
  exit 1
fi

mapfile -t project_dirs < <(
  find "${SOURCE_ROOT}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' \
    | grep -E "${SPOTTER_DIR_PATTERN}|${SPOTTER_WORKTREES_PATTERN}" \
    | sort
)

if [[ "${#project_dirs[@]}" -eq 0 ]]; then
  echo "no spotter project directories found under ${SOURCE_ROOT}" >&2
  exit 1
fi

candidate_file="${tmp_dir}/candidates.tsv"
selected_file="${tmp_dir}/selected.tsv"
sorted_file="${tmp_dir}/sorted.tsv"

touch "${candidate_file}"

for project_dir in "${project_dirs[@]}"; do
  while IFS= read -r session_file; do
    [[ -f "${session_file}" ]] || continue

    line_count="$(wc -l < "${session_file}" | tr -d ' ')"
    session_id="$(
      grep -m1 -oE '"sessionId":"[^"]+"' "${session_file}" \
        | sed -E 's/.*"sessionId":"([^"]+)".*/\1/' \
        || true
    )"

    if [[ -z "${session_id}" ]]; then
      session_id="$(basename "${session_file}" .jsonl)"
    fi

    has_subagent=0
    subagents_dir="$(dirname "${session_file}")/${session_id}/subagents"

    if compgen -G "${subagents_dir}/*.jsonl" >/dev/null 2>&1; then
      has_subagent=1
    elif grep -qiE 'subagent|agent_id|agent-' "${session_file}"; then
      has_subagent=1
    fi

    rel_path="${session_file#${SOURCE_ROOT}/}"
    printf '%s\t%s\t%s\t%s\n' \
      "${line_count}" \
      "${has_subagent}" \
      "${rel_path}" \
      "${session_id}" >> "${candidate_file}"
  done < <(find "${SOURCE_ROOT}/${project_dir}" -maxdepth 1 -type f -name '*.jsonl' | sort)
done

if [[ ! -s "${candidate_file}" ]]; then
  echo "no transcript files found in spotter project directories" >&2
  exit 1
fi

sort -t$'\t' -k1,1nr -k3,3 "${candidate_file}" > "${sorted_file}"
sed -n "1,${MAX_FILES}p" "${sorted_file}" > "${selected_file}"

if ! awk -F'\t' '$2 == 1 { found = 1 } END { exit found ? 0 : 1 }' "${selected_file}"; then
  first_subagent="$(awk -F'\t' '$2 == 1 { print; exit }' "${candidate_file}")"
  if [[ -n "${first_subagent}" ]]; then
    sed -i '$d' "${selected_file}"
    printf '%s\n' "${first_subagent}" >> "${selected_file}"
    awk '!seen[$0]++' "${selected_file}" > "${selected_file}.uniq"
    mv "${selected_file}.uniq" "${selected_file}"
  fi
fi

mkdir -p "${DEST_ROOT}"
find "${DEST_ROOT}" -mindepth 1 \
  ! -name 'README.md' \
  ! -name 'short.jsonl' \
  ! -name 'tool_heavy.jsonl' \
  ! -name 'subagent.jsonl' \
  ! -name 'short.terminal.txt' \
  ! -name 'short.terminal.stripped.txt' \
  ! -name 'tool_heavy.terminal.txt' \
  ! -name 'tool_heavy.terminal.stripped.txt' \
  ! -name 'subagent.terminal.txt' \
  ! -name 'subagent.terminal.stripped.txt' \
  -exec rm -rf {} +

sanitize_jsonl() {
  local source_file="$1"
  local target_file="$2"

  perl -pe '
    s#/home/[A-Za-z0-9._-]+/#/home/USER/#g;
    s#-home-[A-Za-z0-9._-]+-projects-#-home-USER-projects-#g;
    s/[A-Za-z0-9._%+-]+\@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g;
    s/"signature":"[^"]*"/"signature":"[REDACTED_SIGNATURE]"/g;
    s/\b(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9\-_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z\-_]{35})\b/[REDACTED_SECRET]/g;
  ' "${source_file}" > "${target_file}"
}

copied_sessions=0
copied_subagent_files=0

while IFS=$'\t' read -r _line_count _has_subagent rel_path session_id; do
  source_file="${SOURCE_ROOT}/${rel_path}"
  target_file="${DEST_ROOT}/${session_id}.jsonl"

  if [[ -e "${target_file}" ]]; then
    continue
  fi

  sanitize_jsonl "${source_file}" "${target_file}"
  copied_sessions=$((copied_sessions + 1))

  subagents_source="$(dirname "${source_file}")/${session_id}/subagents"
  if [[ -d "${subagents_source}" ]]; then
    while IFS= read -r sub_file; do
      rel_sub="${sub_file#$(dirname "${source_file}")/}"
      dest_sub="${DEST_ROOT}/${rel_sub}"
      mkdir -p "$(dirname "${dest_sub}")"
      sanitize_jsonl "${sub_file}" "${dest_sub}"
      copied_subagent_files=$((copied_subagent_files + 1))
    done < <(find "${subagents_source}" -type f -name '*.jsonl' | sort)
  fi
done < "${selected_file}"

if [[ "${copied_sessions}" -eq 0 ]]; then
  echo "no sessions copied; aborting" >&2
  exit 1
fi

manifest_path="${DEST_ROOT}/README.md"
{
  echo "# Transcript Fixtures"
  echo
  echo "- Snapshot date: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "- Source root: ${SOURCE_ROOT}"
  echo "- Included projects: ${project_dirs[*]}"
  echo "- Selected sessions: ${copied_sessions}"
  echo "- Selected subagent files: ${copied_subagent_files}"
  echo "- Selection rule: top ${MAX_FILES} by line count, force at least one subagent-capable session when available"
  echo "- Sanitization: usernames, emails, signature values, and common token patterns are redacted"
  echo
  echo "## Selected Sessions"
  echo
  while IFS=$'\t' read -r line_count has_subagent rel_path session_id; do
    if [[ -f "${DEST_ROOT}/${session_id}.jsonl" ]]; then
      echo "- \`${session_id}.jsonl\` from \`${rel_path}\` (${line_count} lines, subagent_hint=${has_subagent})"
    fi
  done < "${selected_file}"
} > "${manifest_path}"

echo "snapshot complete:"
echo "  source: ${SOURCE_ROOT}"
echo "  dest:   ${DEST_ROOT}"
echo "  copied sessions: ${copied_sessions}"
echo "  copied subagent files: ${copied_subagent_files}"
