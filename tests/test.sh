#!/usr/bin/env bash
# Offline checks for the hook script and the settings it reads: URL
# normalisation, which config file wins, which hosts a channel may live on,
# and that no setting can run a command. No network.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }

tmp="$(mktemp -d)"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" TMPDIR="$tmp"
mkdir -p "$XDG_CONFIG_HOME/mast"
unset MAST_CHANNEL_URL CLAUDE_PLUGIN_OPTION_CHANNEL_URL MAST_ALLOWED_HOSTS MAST_STOP_MIN_SECS

. scripts/lib.sh

t() { local got; got="$(MAST_CHANNEL_URL="$1" mast_channel_url)"; [[ "$got" == "$2" ]] && ok "url $1" || bad "url $1 -> $got"; }
t "mk_abc" "https://mast.tissue.dev/mk_abc"
t "https://mast.tissue.dev/m/mk_abc" "https://mast.tissue.dev/mk_abc"
t "https://mast.tissue.dev/mk_abc/" "https://mast.tissue.dev/mk_abc"
t " https://MAST.tissue.dev/mk_abc " "https://MAST.tissue.dev/mk_abc"
refuse() { ( MAST_CHANNEL_URL="$1" mast_channel_url >/dev/null ) && bad "refuses $1" || ok "refuses $1"; }
refuse "ftp://x"
refuse "http://mast.tissue.dev/mk_abc"
refuse "https://evil.example/mk_abc"
refuse "https://mast.tissue.dev@evil.example/mk_abc"
refuse "https://mast.tissue.dev.evil.example/mk_abc"
refuse "https://mast.tissue.dev:8443/mk_abc"
[[ "$(MAST_ALLOWED_HOSTS="a.example, mast.example" MAST_CHANNEL_URL=https://mast.example/mk_x mast_channel_url)" == "https://mast.example/mk_x" ]] \
  && ok "MAST_ALLOWED_HOSTS admits a host" || bad "MAST_ALLOWED_HOSTS"
echo "self.example" > "$XDG_CONFIG_HOME/mast/allowed_hosts"
[[ "$(MAST_CHANNEL_URL=https://self.example/mk_x mast_channel_url)" == "https://self.example/mk_x" ]] \
  && ok "allowed_hosts file admits a host" || bad "allowed_hosts file"
rm "$XDG_CONFIG_HOME/mast/allowed_hosts"

# Which file wins.
proj="$tmp/proj"; mkdir -p "$proj/.claude"
printf -- '---\nchannel_url: mk_project\nstop_min_secs: 7\n---\n' > "$proj/.claude/mast.local.md"
[[ "$(mast_channel_url "$proj")" == "https://mast.tissue.dev/mk_project" ]] && ok "reads an untracked project file" || bad "untracked project file"
[[ "$(mast_setting stop_min_secs "$proj")" == "7" ]] && ok "reads a project setting" || bad "project setting"
echo "mk_machine" > "$XDG_CONFIG_HOME/mast/channel"
[[ "$(mast_channel_url "$proj")" == "https://mast.tissue.dev/mk_machine" ]] && ok "per-machine channel wins over the project" || bad "machine vs project"
rm "$XDG_CONFIG_HOME/mast/channel"
printf -- '---\nstop_min_secs: 300\n---\n' > "$XDG_CONFIG_HOME/mast/settings.md"
[[ "$(mast_setting stop_min_secs "$proj")" == "300" ]] && ok "settings.md wins over the project" || bad "settings.md vs project"
rm "$XDG_CONFIG_HOME/mast/settings.md"
if command -v git >/dev/null 2>&1; then
  git -C "$proj" init -q && git -C "$proj" add .claude/mast.local.md
  ( mast_channel_url "$proj" >/dev/null ) && bad "ignores a git-tracked project file" || ok "ignores a git-tracked project file"
  [[ -z "$(mast_setting stop_min_secs "$proj")" ]] && ok "ignores settings in a tracked file" || bad "tracked settings"
  rm -rf "$proj/.git"
fi

# No setting reaches arithmetic unchecked.
mast_valid_setting stop_min_secs 'a[$(id)]' && bad "rejects a hostile stop_min_secs" || ok "rejects a hostile stop_min_secs"
mast_valid_setting stop_priority 'page' && ok "accepts page" || bad "accepts page"
mast_valid_setting stop_priority 'urgent' && bad "rejects unknown priority" || ok "rejects unknown priority"

export MAST_DRY_RUN=1
run() { printf '%s' "$1" | bash scripts/notify.sh 2>&1 >/dev/null; }
stamps="$tmp/mast-claude-$(id -u)"
long_turn() { mkdir -p "$stamps"; echo 0 > "$stamps/$1.start"; }

pwn="$tmp/pwned"
printf -- '---\nchannel_url: mk_project\nstop_min_secs: HOME[$(touch %s)]\n---\n' "$pwn" > "$proj/.claude/mast.local.md"
long_turn h1
out="$(run '{"hook_event_name":"Stop","session_id":"h1","cwd":"'"$proj"'","last_assistant_message":"done"}')"
[[ ! -e "$pwn" ]] && ok "hostile stop_min_secs in mast.local.md runs nothing" || bad "stop_min_secs injection ran"
grep -q 'title=proj finished' <<<"$out" && ok "falls back to the default" || bad "fallback: $out"
long_turn h2
out="$(MAST_STOP_MIN_SECS='HOME[$(touch '"$pwn"')]' run '{"hook_event_name":"Stop","session_id":"h2","cwd":"'"$proj"'"}')"
[[ ! -e "$pwn" ]] && ok "hostile MAST_STOP_MIN_SECS runs nothing" || bad "env injection ran"
mkdir -p "$stamps"; printf 'HOME[$(touch %s)]' "$pwn" > "$stamps/h3.start"
out="$(run '{"hook_event_name":"Stop","session_id":"h3","cwd":"'"$proj"'"}')"
[[ ! -e "$pwn" && -z "$out" ]] && ok "hostile stamp runs nothing" || bad "stamp injection: $out"

printf -- '---\nchannel_url: https://evil.example/mk_x\n---\n' > "$proj/.claude/mast.local.md"
out="$(run '{"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"h4","cwd":"'"$proj"'"}')"
[[ -z "$out" ]] && ok "project file can't point the hook at another host" || bad "redirect: $out"

export MAST_CHANNEL_URL=mk_test
out="$(run '{"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"abcdef1234","cwd":"/x/proj","message":"Claude needs your permission to use Bash"}')"
grep -q 'priority=page' <<<"$out" && grep -q 'key=claude-abcdef12-blocked' <<<"$out" && grep -q 'ack=required' <<<"$out" \
  && ok "permission prompt pages with ack" || bad "permission prompt: $out"
out="$(run '{"hook_event_name":"Stop","session_id":"s2","cwd":"/x/proj"}')"
[[ -z "$out" ]] && ok "Stop without stamp is silent" || bad "Stop without stamp: $out"

rm -rf "$tmp"
[[ $fail -eq 0 ]] && echo "all passed" || { echo "FAILED"; exit 1; }
