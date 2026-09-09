#!/usr/bin/env bash
# Shared by every script in this plugin. Sourced, not executed.
#
# Resolves the channel URL, normalises it, and wraps the one HTTP call the
# plugin makes: POST <channel-url> with form fields. Mast's ingest surface is
# documented at https://tissue.systems/docs/mast/connect/#send-fields.

MAST_PLUGIN_VERSION="0.1.0"
MAST_DEFAULT_HOST="https://mast.tissue.dev"

# Per-project settings live in .claude/mast.local.md (YAML frontmatter), the
# Claude Code plugin-settings convention. The file is user-managed and belongs
# in .gitignore: it may carry a channel URL, which is a send credential.
mast_settings_file() {
  local cwd="${1:-$PWD}"
  printf '%s/.claude/mast.local.md' "$cwd"
}

# mast_setting <key> [cwd] — one frontmatter value, or empty.
mast_setting() {
  local key="$1" file
  file="$(mast_settings_file "${2:-$PWD}")"
  [[ -f "$file" ]] || return 0
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$file" \
    | sed -n "s/^${key}:[[:space:]]*//p" | head -n1 | sed 's/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/'
}

# Channel URL resolution order:
#   1. MAST_CHANNEL_URL in the environment
#   2. CLAUDE_PLUGIN_OPTION_CHANNEL_URL (plugin userConfig, hook environments)
#   3. channel_url in .claude/mast.local.md of the working directory
#   4. ${XDG_CONFIG_HOME:-~/.config}/mast/channel (first non-comment line)
# Any of them may hold a full URL (https://mast.tissue.dev/mk_…, with or
# without the /m/ prefix) or a bare mk_ key.
mast_channel_url() {
  local cwd="${1:-$PWD}" raw="" file
  raw="${MAST_CHANNEL_URL:-}"
  # Set by Claude Code from the plugin's userConfig.channel_url (prompted at
  # /plugin install time); present only in hook environments.
  [[ -n "$raw" ]] || raw="${CLAUDE_PLUGIN_OPTION_CHANNEL_URL:-}"
  [[ -n "$raw" ]] || raw="$(mast_setting channel_url "$cwd")"
  if [[ -z "$raw" ]]; then
    file="${XDG_CONFIG_HOME:-$HOME/.config}/mast/channel"
    [[ -f "$file" ]] && raw="$(grep -v '^[[:space:]]*#' "$file" | grep -m1 .)"
  fi
  raw="${raw//[[:space:]]/}"
  [[ -n "$raw" ]] || return 1
  case "$raw" in
    mk_*) printf '%s/%s\n' "$MAST_DEFAULT_HOST" "$raw" ;;
    https://*/m/mk_*) printf '%s\n' "${raw/\/m\/mk_//mk_}" ;;
    https://*) printf '%s\n' "${raw%/}" ;;
    *) return 1 ;;
  esac
}

# mast_send <url> field=value ... — POST one message, print the 202 body.
# Form-encoded on purpose: no JSON escaping in shell, and it is the shape the
# docs lead with. Fields are passed straight through (title, body, priority,
# key, url, url_title, ack, retry, expire).
mast_send() {
  local url="$1"; shift
  local args=()
  local f
  for f in "$@"; do args+=(--data-urlencode "$f"); done
  curl -sS --max-time "${MAST_HTTP_TIMEOUT:-8}" -X POST "$url" \
    -H "User-Agent: mast-claude-plugin/${MAST_PLUGIN_VERSION}" \
    "${args[@]}"
}

# mast_message_state <url> <mm_id> — the state of one message this key sent:
# queued | muted | deduped | suppressed | acked | resolved | expired.
mast_message_state() {
  local url="$1" id="$2"
  curl -sS --max-time "${MAST_HTTP_TIMEOUT:-8}" "${url}/messages/${id}" \
    -H "User-Agent: mast-claude-plugin/${MAST_PLUGIN_VERSION}" \
    | mast_json_field state
}

# mast_json_field <name> — pull one top-level string/number out of JSON on stdin.
# jq when present; a sed fallback so the hook has no hard dependency.
mast_json_field() {
  local name="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$name" '.[$k] // empty' 2>/dev/null
  else
    sed -n 's/.*"'"$name"'"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\)"\{0,1\}.*/\1/p' | head -n1
  fi
}

# mast_truncate <n> — cut stdin to n characters, single line.
mast_truncate() {
  tr '\n' ' ' | cut -c1-"$1" | sed 's/[[:space:]]*$//'
}
