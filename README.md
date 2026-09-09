# Mast Pager for Claude Code

Your phone buzzes, and keeps buzzing until you acknowledge, when Claude Code is blocked on you.

[Mast](https://tissue.systems/mast) is an iPhone and Apple Watch pager. This plugin connects a
Claude Code session to one Mast channel. It needs no account, no token and no server: a channel
URL from the app is the whole configuration.

## Requirements

- **The Mast Pager app** on an iPhone, from the
  [App Store](https://apps.apple.com/us/app/mast-pager/id6805232044). It is a one-time purchase
  of $4.99, not a subscription. Pages mirror to a paired Apple Watch.
- **A channel** created in the app. The app hands you its URL; that URL is what the plugin sends
  to, and it is the only secret involved.
- `bash` and `curl` on the machine running Claude Code. `jq` is used when present.

Without the app or a channel URL the plugin does nothing: every hook exits quietly and Claude Code
runs as before.

## What it does

| When | You get |
|---|---|
| Claude is waiting on a permission prompt | A page that repeats until you acknowledge |
| Claude asked a question and has been idle for a minute | A page |
| An MCP server is asking you for input | A page |
| A turn that ran two minutes or longer finishes | One ordinary notification with the last thing Claude said |
| A turn dies on an API error | One time-sensitive notification |

The card's title is the project directory, so the lock screen answers "which project wants me".
A burst of permission prompts from one session folds into the card already on the phone.

Skills, invoked as `/mast:<name>`:

- `setup`: get a channel URL from the app and store it.
- `test`: report the configuration and send one test message.
- `page`: "page me when the build is done". Claude sends one message on your behalf.
- `ask`: "get my OK on the phone before you deploy". Claude pages you and waits for the
  acknowledgement before continuing. Silence is treated as no.
- `app-alerts`: teaches Claude to wire Mast alerts and a vitals heartbeat into the app it is
  building for you.

## Install

```
/plugin marketplace add tissue-systems/mast-claude-plugin
/plugin install mast@mast
/mast:setup
```

Hooks load at session start. Restart the session after installing.

## Configuration

The channel URL is read from, in order:

1. `MAST_CHANNEL_URL` in the environment (or the `env` block of `~/.claude/settings.json`)
2. The `channel_url` plugin option Claude Code asks for at install time. This reaches the hooks
   only, not the `/mast:*` skills, so also set one of the sources below.
3. `channel_url:` in the frontmatter of `.claude/mast.local.md` in the project (per project)
4. `~/.config/mast/channel`, a file holding the URL (per machine)

A full URL (`https://mast.tissue.dev/mk_…`) or a bare `mk_…` key both work. The URL is a
send credential: keep it out of git.

Optional, as frontmatter keys in `.claude/mast.local.md` or as environment variables:

| Frontmatter | Environment | Default | |
|---|---|---|---|
| `on_stop` | `MAST_ON_STOP` | `true` | Notify when a turn finishes |
| `stop_min_secs` | `MAST_STOP_MIN_SECS` | `120` | Only for turns at least this long |
| `blocked_priority` | `MAST_BLOCKED_PRIORITY` | `page` | Priority when Claude is waiting on you |
| `stop_priority` | `MAST_STOP_PRIORITY` | `normal` | Priority of the turn-finished card |

**Raise the channel's ceiling to `page` in the Mast app.** A new channel starts at `loud`, and
every send is clamped to the ceiling, so until it is raised the "blocked on you" page arrives as
one time-sensitive card that does not repeat.

## How it works

`hooks/hooks.json` runs `scripts/notify.sh` on the `Notification`, `Stop`, `StopFailure`,
`UserPromptSubmit` and `SessionEnd` events. The script reads the event JSON on stdin and makes
one form-encoded `POST` to the channel URL with `curl`. `UserPromptSubmit` only stamps the
turn's start time so `Stop` can skip short turns. Every path exits 0 and the request has an
eight-second timeout: a failed page never stalls the agent.

`scripts/mast-ask.sh` sends a message with `ack=required` and polls
`GET <channel-url>/messages/<id>` until the state is `acked`. The channel key can read only its
own messages, which is why no account is needed.

## Test the hook by hand

```bash
echo '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Bash needs approval","session_id":"abc12345","cwd":"'"$PWD"'"}' \
  | MAST_DRY_RUN=1 bash scripts/notify.sh
```

## On the phone

A page from a blocked session looks like this on the lock screen, and repeats until acknowledged:

```
cell needs a permission
Claude needs your permission to use Bash
```

Acknowledge it from the notification, from the app, or from the Watch. A second permission
prompt from the same session folds into the card already on the phone instead of stacking.

## Links

- Mast: https://tissue.systems/mast
- Mast Pager on the App Store: https://apps.apple.com/us/app/mast-pager/id6805232044
- Sending to a channel, all fields and limits: https://tissue.systems/docs/mast/connect/
  (title 250 characters, body 4096, 60 sends a minute per channel)
- Which priority to use for what: https://tissue.systems/mast/guide
