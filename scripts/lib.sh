#!/usr/bin/env bash
# Shared by every script in this plugin. Sourced, not executed.
#
# Resolves the channel URL, normalises it, and wraps the one HTTP call the
# plugin makes: POST <channel-url> with form fields. Mast's ingest surface is
# documented at https://tissue.systems/docs/mast/connect/#send-fields.

MAST_PLUGIN_VERSION="0.1.1"
MAST_DEFAULT_HOST="https://mast.tissue.dev"

# Per-project settings live in .claude/mast.local.md (YAML frontmatter), the
# Claude Code plugin-settings convention. The file is user-managed and belongs
# in .gitignore: it may carry a channel URL, which is a send credential.
mast_settings_file() {
  local cwd="${1:-$PWD}"
  printf '%s/.claude/mast.local.md' "$cwd"
}

# Per-machine files: ~/.config/mast/channel (the URL), settings.md (the same
# frontmatter keys as mast.local.md) and allowed_hosts (extra channel hosts,
# one per line).
mast_user_dir() {
  printf '%s/mast' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# mast_project_file [cwd] — the project settings file, if it may be read.
# A mast.local.md that git tracks came with the repository, so whoever wrote
# the repository chose its values. That file is ignored: a cloned project must
# not decide where the hooks send session text, or feed values to the hook.
mast_project_file() {
  local file
  file="$(mast_settings_file "${1:-$PWD}")"
  [[ -f "$file" ]] || return 1
  if command -v git >/dev/null 2>&1 \
    && git -C "$(dirname "$file")" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    return 1
  fi
  printf '%s' "$file"
}

# mast_frontmatter <file> <key> — one frontmatter value, or empty.
mast_frontmatter() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$file" \
    | sed -n "s/^${key}:[[:space:]]*//p" | head -n1 | sed 's/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/'
}

# mast_setting <key> [cwd] — the per-machine settings.md wins over the
# project's mast.local.md, so a project can't override what the user set.
mast_setting() {
  local key="$1" cwd="${2:-$PWD}" v="" file
  v="$(mast_frontmatter "$(mast_user_dir)/settings.md" "$key")"
  if [[ -z "$v" ]] && file="$(mast_project_file "$cwd")"; then
    v="$(mast_frontmatter "$file" "$key")"
  fi
  printf '%s' "$v"
}

# mast_valid_setting <key> <value> — true when value is legal for key. The
# hook does arithmetic on stop_min_secs, and bash evaluates command
# substitutions hidden in an arithmetic operand, so nothing reaches (( ))
# without passing this first.
mast_valid_setting() {
  case "$1" in
    stop_min_secs) [[ "$2" =~ ^[0-9]{1,7}$ ]] ;;
    on_stop) [[ "$2" =~ ^(true|false|1|0|on|off)$ ]] ;;
    blocked_priority|stop_priority) [[ "$2" =~ ^(quiet|normal|loud|page)$ ]] ;;
    *) return 1 ;;
  esac
}

# mast_host_allowed <https-url> — the URL's host is mast.tissue.dev, or one the
# user listed in MAST_ALLOWED_HOSTS (space or comma separated) or in
# ~/.config/mast/allowed_hosts. The match is exact: no userinfo, and a port
# has to be listed with the host.
mast_host_allowed() {
  local rest="${1#https://}" host allowed h
  host="$(printf '%s' "${rest%%/*}" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$host" && "$host" != *@* ]] || return 1
  allowed="mast.tissue.dev ${MAST_ALLOWED_HOSTS:-}"
  [[ -f "$(mast_user_dir)/allowed_hosts" ]] \
    && allowed="$allowed $(grep -v '^[[:space:]]*#' "$(mast_user_dir)/allowed_hosts")"
  for h in ${allowed//,/ }; do
    [[ "$host" == "$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')" ]] && return 0
  done
  return 1
}

# Channel URL resolution order:
#   1. MAST_CHANNEL_URL in the environment
#   2. CLAUDE_PLUGIN_OPTION_CHANNEL_URL (plugin userConfig, hook environments)
#   3. ${XDG_CONFIG_HOME:-~/.config}/mast/channel (first non-comment line)
#   4. channel_url in ~/.config/mast/settings.md, then in .claude/mast.local.md
#      of the working directory when git does not track that file
# Any of them may hold a full URL (https://mast.tissue.dev/mk_…, with or
# without the /m/ prefix) or a bare mk_ key. A URL on a host other than
# mast.tissue.dev is refused unless the user allowed that host.
mast_channel_url() {
  local cwd="${1:-$PWD}" raw="" file url
  raw="${MAST_CHANNEL_URL:-}"
  # Set by Claude Code from the plugin's userConfig.channel_url (prompted at
  # /plugin install time); present only in hook environments.
  [[ -n "$raw" ]] || raw="${CLAUDE_PLUGIN_OPTION_CHANNEL_URL:-}"
  if [[ -z "$raw" ]]; then
    file="$(mast_user_dir)/channel"
    [[ -f "$file" ]] && raw="$(grep -v '^[[:space:]]*#' "$file" | grep -m1 .)"
  fi
  [[ -n "$raw" ]] || raw="$(mast_setting channel_url "$cwd")"
  raw="${raw//[[:space:]]/}"
  [[ -n "$raw" ]] || return 1
  case "$raw" in
    mk_*) url="$MAST_DEFAULT_HOST/$raw" ;;
    https://*/m/mk_*) url="${raw/\/m\/mk_//mk_}" ;;
    https://*) url="${raw%/}" ;;
    *) return 1 ;;
  esac
  mast_host_allowed "$url" || return 1
  printf '%s\n' "$url"
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
