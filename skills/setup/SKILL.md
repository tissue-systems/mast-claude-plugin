---
name: setup
description: This skill should be used when the user asks to "set up mast", "configure the pager", "connect my phone", "where do I put the channel URL", "mast setup", or right after installing the mast plugin. Walks through getting a channel URL from the Mast app and storing it where the plugin reads it, then sends a test page.
disable-model-invocation: true
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/*)
  - Bash(mkdir *)
  - Bash(chmod *)
  - Bash(cat *)
  - Read
  - Write
  - AskUserQuestion
---

# Set up the Mast pager

Mast is an iPhone and Apple Watch pager app. A channel URL is a send credential:
anything that can POST to it can make the owner's phone buzz. This plugin needs one such URL.

## Steps

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-status.sh`. If it reports a configured channel,
   skip to step 4.

2. Ask the user for a channel URL, and tell them how to get one if they do not have it:
   - Install Mast Pager from the App Store (https://apps.apple.com/us/app/mast-pager/id6805232044).
   - In the app, create a channel named for this machine or for Claude Code, and copy its URL.
     It looks like `https://mast.tissue.dev/mk_…`. A bare `mk_…` key is accepted as well.
   - **Raise the channel's ceiling to `page` in the app** (channel settings). Every new channel
     starts with a ceiling of `loud`, and a `loud` card sounds once and stops. Only a `page`
     repeats until acknowledged, which is the whole point of the plugin's "blocked on you" alert.

3. Store it. Offer these, in this order of preference:
   - **Per machine (recommended):** write the URL as the only line of
     `~/.config/mast/channel`, then `chmod 600` it and `chmod 700 ~/.config/mast`. Every
     project on this machine pages the same channel; the card's title names the project.
   - **Per project:** write `.claude/mast.local.md` in the project root with YAML frontmatter
     `channel_url: https://mast.tissue.dev/mk_…`. Confirm `.claude/*.local.md` is in the
     project's `.gitignore` before writing, and add it if not. This wins over the per-machine file.
   - **Environment:** `MAST_CHANNEL_URL` in the shell, or in the `env` block of
     `~/.claude/settings.json`. This wins over both files.
   Never write the URL into a file that is committed.

4. Optional settings, all in the same `.claude/mast.local.md` frontmatter or as environment
   variables. Mention them; do not set them unless asked.

   | Setting | Env | Default | Meaning |
   |---|---|---|---|
   | `on_stop` | `MAST_ON_STOP` | `true` | Notify when a turn finishes |
   | `stop_min_secs` | `MAST_STOP_MIN_SECS` | `120` | Only notify for turns at least this long |
   | `blocked_priority` | `MAST_BLOCKED_PRIORITY` | `page` | Priority when Claude is waiting on the human |
   | `stop_priority` | `MAST_STOP_PRIORITY` | `normal` | Priority for the turn-finished card |

5. Send a test: run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-send.sh "Claude Code" "Mast is set up on $(hostname)" page --ack`.
   Ask the user whether the card repeated. If it arrived once and went quiet, the channel's
   ceiling is still `loud`; point them back to step 2.

6. Explain what happens from here in three sentences: a permission prompt, an unanswered
   question, or an MCP elicitation pages the phone and repeats until acknowledged; a turn that
   ran longer than two minutes sends one ordinary notification when it ends; an API error that
   ends a turn sends a time-sensitive one. Hooks load at session start, so a fresh install needs
   the session restarted.
