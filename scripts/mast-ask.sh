#!/usr/bin/env bash
# Page the owner and wait for the acknowledgement.
#
#   mast-ask.sh "title" "body" [--timeout SECS] [--priority page|loud|normal]
#
# Sends one message with ack required, then polls the message's state through
# the same channel key until it is acknowledged. The key can read only its own
# channel's messages, so this needs no account and no token.
#
# Exit codes, for the skill that calls this:
#   0  acked     — the human saw it and tapped acknowledge
#   3  resolved  — the human resolved it without acknowledging
#   4  expired   — mast stopped repeating before anyone answered
#   5  timeout   — this script gave up waiting (the page may still be live)
#   6  no channel configured
#   7  the send was refused (the response is printed)

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

title="${1:-}"; body="${2:-}"; shift 2 2>/dev/null || true
timeout=540; priority="page"; poll=10
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) timeout="$2"; shift 2 ;;
    --priority) priority="$2"; shift 2 ;;
    --poll) poll="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$title$body" ]] || { echo "usage: mast-ask.sh TITLE BODY [--timeout SECS] [--priority P]" >&2; exit 2; }

url="$(mast_channel_url)" || { echo "No mast channel configured. Run /mast:setup." >&2; exit 6; }

# expire = how long mast keeps repeating; matched to how long we will wait so
# a page nobody answered does not keep buzzing after the agent moved on.
resp="$(mast_send "$url" "title=$title" "body=$body" "priority=$priority" \
        "ack=required" "expire=$(( timeout < 60 ? 60 : timeout ))" \
        "key=claude-ask-$(date +%s)")" || { echo "send failed: $resp" >&2; exit 7; }
id="$(printf '%s' "$resp" | mast_json_field id)"
state="$(printf '%s' "$resp" | mast_json_field state)"
if [[ -z "$id" ]]; then echo "send refused: $resp" >&2; exit 7; fi
echo "sent $id ($state); waiting up to ${timeout}s for an acknowledgement" >&2

deadline=$(( $(date +%s) + timeout ))
while (( $(date +%s) < deadline )); do
  sleep "$poll"
  state="$(mast_message_state "$url" "$id" 2>/dev/null)"
  case "$state" in
    acked)    echo "acked"; exit 0 ;;
    resolved) echo "resolved"; exit 3 ;;
    expired)  echo "expired"; exit 4 ;;
  esac
done
echo "timeout (message $id still ${state:-unknown})"
exit 5
