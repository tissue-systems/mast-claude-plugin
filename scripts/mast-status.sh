#!/usr/bin/env bash
# Report where the channel URL comes from, without printing the key.
set -u
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

src="none"
if [[ -n "${MAST_CHANNEL_URL:-}" ]]; then src="MAST_CHANNEL_URL environment variable"
elif [[ -n "${CLAUDE_PLUGIN_OPTION_CHANNEL_URL:-}" ]]; then src="plugin option channel_url"
elif [[ -n "$(mast_setting channel_url)" ]]; then src="$(mast_settings_file) (channel_url)"
elif [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/mast/channel" ]]; then src="${XDG_CONFIG_HOME:-$HOME/.config}/mast/channel"
fi
if url="$(mast_channel_url)"; then
  key="${url##*/}"
  echo "channel: configured (${key:0:6}…${key: -4}) from $src"
else
  echo "channel: not configured"
  echo "(a channel_url entered at /plugin install time reaches the hooks only; skills need one of the sources above)"
fi
echo "on_stop: ${MAST_ON_STOP:-$(mast_setting on_stop)}"
echo "stop_min_secs: ${MAST_STOP_MIN_SECS:-$(mast_setting stop_min_secs)}"
echo "blocked_priority: ${MAST_BLOCKED_PRIORITY:-$(mast_setting blocked_priority)}"
echo "stop_priority: ${MAST_STOP_PRIORITY:-$(mast_setting stop_priority)}"
echo "(empty means the default: on_stop true, stop_min_secs 120, blocked page, stop normal)"
