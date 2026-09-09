---
name: ask
description: This skill should be used when Claude needs a human decision and the user is not at the terminal, or when the user says "page me and wait", "ask me on my phone before you deploy", "get my OK before continuing", "do not proceed until I acknowledge". Sends a page that repeats until acknowledged and blocks until the acknowledgement arrives or the wait times out.
argument-hint: "[question]"
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-ask.sh *)
---

# Page and wait for an acknowledgement

The phone can answer with exactly one bit: **acknowledge**. Phrase the page so that
acknowledging means "go ahead with what the card says", and so that silence is safe.

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-ask.sh "<title>" "<body>" [--timeout <secs>] [--priority page]
```

- **title**: the decision in a few words: `Deploy 2026.09.010 to prod?`
- **body**: what acknowledging authorises, and what happens if nobody answers:
  `Ack to deploy to both edges. If nobody acks in 9 minutes I stop and wait in the terminal.`
- **--timeout**: how long to wait. Default 540 seconds, which fits inside the shell tool's
  limit; do not exceed 570. Mast stops repeating the page at the same moment.

The script exits 0 and prints `acked` when the human acknowledged. Then, and only then, do
what the card said.

Any other exit is **not consent**:
- `resolved` (exit 3): the human closed the incident without acknowledging. Treat as "no".
- `expired` or `timeout` (exit 4, 5): nobody answered. Stop, report that you paged and got
  no answer, and wait for the user in the terminal. Do not page again on your own.
- `No mast channel configured` (exit 6): tell the user to run `/mast:setup`, then wait in the
  terminal as you would without the plugin.
- `send failed` / `send refused` (exit 7): report the response and wait in the terminal.

Use this for irreversible or outward-facing actions when the user has walked away. Never use it
to skip a permission prompt: the prompt in the terminal remains the authority for tool use.
