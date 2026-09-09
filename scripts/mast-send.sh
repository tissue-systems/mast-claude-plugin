#!/usr/bin/env bash
# Send one message to the configured channel.
#
#   mast-send.sh "title" "body" [priority] [--url URL --url-title TEXT --key K]
#
# Prints the 202 body ({"ok":true,"id":"mm_…","state":"queued"}).

set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

positional=(); fields=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) fields+=("url=${2:-}"); shift 2 ;;
    --url-title) fields+=("url_title=${2:-}"); shift 2 ;;
    --key) fields+=("key=${2:-}"); shift 2 ;;
    --ack) fields+=("ack=required"); shift ;;
    --*) echo "unknown argument: $1" >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
title="${positional[0]:-}"; body="${positional[1]:-}"; priority="${positional[2]:-normal}"
fields=("title=$title" "body=$body" "priority=$priority" "${fields[@]}")
[[ -n "$title$body" ]] || { echo "usage: mast-send.sh TITLE BODY [PRIORITY] [--url U --url-title T --key K --ack]" >&2; exit 2; }
case "$priority" in quiet|normal|loud|page) ;; *) echo "priority must be quiet, normal, loud or page" >&2; exit 2 ;; esac

url="$(mast_channel_url)" || { echo "No mast channel configured. Run /mast:setup." >&2; exit 6; }
mast_send "$url" "${fields[@]}"
echo
