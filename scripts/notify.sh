#!/usr/bin/env bash
# Hook handler. Claude Code runs this with the hook event as JSON on stdin and
# waits for nothing: every path exits 0, prints nothing to stdout, and the HTTP
# call has a hard timeout. A failed page must never stall or block the agent.
#
# Events and what they become on the phone:
#   Notification/permission_prompt    page   — the agent is blocked on a permission
#   Notification/idle_prompt          page   — the agent asked something and nobody answered
#   Notification/elicitation_dialog   page   — an MCP server is asking the human a question
#   Stop                              normal — the turn finished (only after a long turn)
#   StopFailure                       loud   — the turn died on an API error
#   UserPromptSubmit                  —      — stamps the turn start, sends nothing
#   SessionEnd                        —      — removes the stamp
#
# The dedupe key is per session and per kind, so a burst of permission prompts
# from one session folds into the card that is already on the phone.

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

input="$(cat)"
field() { printf '%s' "$input" | mast_json_field "$1"; }

event="$(field hook_event_name)"
session="$(field session_id)"
cwd="$(field cwd)"
[[ -n "$cwd" ]] || cwd="$PWD"
project="$(basename "$cwd")"
short_session="${session:0:8}"

# Turn stamps: the Stop hook fires after every turn, including a two-second
# one while the user is sitting at the terminal. Only a turn that ran at
# least stop_min_secs is worth a notification.
stamp_dir="${TMPDIR:-/tmp}/mast-claude-${UID:-$(id -u)}"
stamp="${stamp_dir}/${session:-nosession}.start"

case "$event" in
  UserPromptSubmit)
    mkdir -p "$stamp_dir" 2>/dev/null && chmod 700 "$stamp_dir" 2>/dev/null
    date +%s > "$stamp" 2>/dev/null
    exit 0 ;;
  SessionEnd)
    rm -f "$stamp" 2>/dev/null
    exit 0 ;;
esac

url="$(mast_channel_url "$cwd")" || exit 0   # not configured: silently do nothing

# Settings (env wins, then .claude/mast.local.md, then the default).
setting() {  # setting <ENV_NAME> <yaml_key> <default>
  local v="${!1:-}"
  [[ -n "$v" ]] || v="$(mast_setting "$2" "$cwd")"
  printf '%s' "${v:-$3}"
}
on_stop="$(setting MAST_ON_STOP on_stop true)"
stop_min="$(setting MAST_STOP_MIN_SECS stop_min_secs 120)"
blocked_priority="$(setting MAST_BLOCKED_PRIORITY blocked_priority page)"
stop_priority="$(setting MAST_STOP_PRIORITY stop_priority normal)"

title="" body="" priority="" key="" extra=()

case "$event" in
  Notification)
    kind="$(field notification_type)"
    message="$(field message | mast_truncate 600)"
    case "$kind" in
      permission_prompt)
        title="$project needs a permission"
        body="${message:-Claude Code is waiting for you to approve a tool call.}" ;;
      idle_prompt)
        title="$project is waiting for you"
        body="${message:-Claude Code asked something and has been idle for a minute.}" ;;
      elicitation_dialog)
        title="$project has a question"
        body="${message:-An MCP server is asking for input.}" ;;
      auth_success|"") exit 0 ;;
      *)
        # A notification type this script does not know. Better a card than
        # silence: the whole point is not missing the moment the agent stops.
        title="$project: $kind"
        body="${message:-Claude Code sent a notification.}" ;;
    esac
    priority="$blocked_priority"
    key="claude-${short_session}-blocked"
    extra+=("ack=required") ;;

  Stop)
    [[ "$on_stop" == "true" || "$on_stop" == "1" || "$on_stop" == "on" ]] || exit 0
    # stop_hook_active means a Stop hook already continued this turn once;
    # do not page twice for one turn.
    [[ "$(field stop_hook_active)" == "true" ]] && exit 0
    if [[ -f "$stamp" ]]; then
      started="$(cat "$stamp" 2>/dev/null || echo 0)"
      elapsed=$(( $(date +%s) - ${started:-0} ))
      (( elapsed >= stop_min )) || exit 0
    else
      # No stamp: an older session, or the stamp dir is unwritable. Without a
      # duration to judge, stay quiet rather than buzz on every short turn.
      exit 0
    fi
    last="$(field last_assistant_message | mast_truncate 400)"
    mins=$(( elapsed / 60 ))
    title="$project finished"
    body="${last:-Claude Code finished a ${mins}-minute turn.}"
    priority="$stop_priority"
    key="claude-${short_session}-stop"
    rm -f "$stamp" 2>/dev/null ;;

  StopFailure)
    err="$(field error | mast_truncate 300)"
    [[ -n "$err" ]] || err="$(field message | mast_truncate 300)"
    title="$project stopped on an error"
    body="${err:-The turn ended on an API error and Claude Code is no longer working.}"
    priority="loud"
    key="claude-${short_session}-failure"
    rm -f "$stamp" 2>/dev/null ;;

  *) exit 0 ;;
esac

if [[ "${MAST_DRY_RUN:-}" == "1" ]]; then
  printf 'POST %s\n  title=%s\n  body=%s\n  priority=%s\n  key=%s\n' \
    "$url" "$title" "$body" "$priority" "$key" >&2
  for f in "${extra[@]+"${extra[@]}"}"; do printf '  %s\n' "$f" >&2; done
  exit 0
fi

mast_send "$url" "title=$title" "body=$body" "priority=$priority" "key=$key" \
  "${extra[@]+"${extra[@]}"}" >/dev/null 2>&1 || true
exit 0
