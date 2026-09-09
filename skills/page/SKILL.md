---
name: page
description: This skill should be used when the user asks Claude to "page me", "text my phone", "notify me when this is done", "alert me if the build fails", "ping my phone", "let me know on my phone", or when a long task Claude was asked to report on has finished or failed and the user is not at the terminal. Sends one message to the owner's Mast channel.
argument-hint: "[message]"
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-send.sh *)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-status.sh)
---

# Page the owner

This makes a human's phone buzz. Send it when asked to, or when the user asked in advance to be
told about an outcome. Do not send progress chatter, and never send more than one message for
one outcome.

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-send.sh "<title>" "<body>" <priority> [--url <link> --url-title <text>] [--key <dedupe-key>] [--ack]
```

- **title**: the project name, or what the user called the task. Under 60 characters.
- **body**: the one fact the user needs, under 300 characters. "Tests green, deployed
  2026.09.010 to both edges" beats a paragraph. No markdown.
- **priority**:
  - `normal` for "done", "finished", routine outcomes.
  - `loud` for failures and anything the user said they care about; it breaks through Focus.
  - `page` only when the user must act now and asked to be woken or interrupted; it repeats
    until acknowledged. Pass `--ack` with it.
  - `quiet` for information the user asked to have logged but not announced.
- **--url**: a link the user can open from the card, when one exists (a PR, a dashboard, a
  failing CI run). `http` or `https` only.
- **--key**: a dedupe key when the same outcome may be reported again inside a few minutes.

The script prints Mast's response. `{"ok":true,…,"state":"queued"}` is success. If it prints
"No mast channel configured", tell the user to run `/mast:setup` and continue without paging.

Say in one line what was sent. Do not paste the response JSON to the user.
