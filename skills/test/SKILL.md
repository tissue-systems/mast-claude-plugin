---
name: test
description: This skill should be used when the user asks to "test mast", "send a test page", "check the pager works", "is mast configured", or "mast status". Reports how the channel is configured and sends one test message.
disable-model-invocation: true
argument-hint: "[priority: quiet|normal|loud|page]"
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/*)
---

# Test the Mast pager

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-status.sh` and report the result. If no channel
   is configured, stop and point the user at `/mast:setup`.
2. Send a test at the requested priority, default `page`:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/mast-send.sh "Claude Code test" "sent from $(basename "$PWD")" ${0:-page} --ack`
3. Report the response. `{"ok":true,"id":"mm_…","state":"queued"}` means Mast stored it and
   pushed it; `muted` means the channel is muted or inside quiet hours; `deduped` means the card
   is already on the phone. A 404 means the URL is wrong or the key was rotated more than seven
   days ago. A 429 is the per-key rate limit of 60 sends a minute.
4. If the priority was `page`, tell the user: if the card sounded once and did not repeat, the
   channel's ceiling is `loud` and must be raised to `page` in the Mast app. The 202 does not
   report the clamp, so only the phone can confirm it.
