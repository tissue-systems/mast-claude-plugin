---
name: app-alerts
description: This skill should be used when the user building an application asks how to "get alerted when my app breaks", "notify me when a payment fails", "page me if the cron job stops", "add error alerts", "monitor my side project", "know when the nightly job dies", or when Claude is wiring error handling, payment webhooks, signups or scheduled jobs into an app and the owner needs to hear about failures on their phone. Teaches the Mast pattern - one POST to a channel URL, dedupe, and a vitals heartbeat for jobs that must not go silent.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# Pager alerts for the app being built

Mast is an iPhone pager. An app alerts its owner with one HTTPS POST to a channel URL, with
no SDK, no account and no API key: the URL is the credential. The owner performs the only human
step. Everything else is code to write.

## The handoff

Ask the owner to open the Mast app, create a channel for this app, and paste its URL. It looks
like `https://mast.tissue.dev/mk_…`. Then:

- Put the URL in the app's secret store (an environment variable such as `MAST_URL`, a CI
  secret, a vault binding). **Never in source.** Rotating the key is one call in the app plus
  one secret update, with seven days of overlap.
- For alerts that must wake someone, the owner also raises the channel's ceiling to `page` in
  the app. A new channel's ceiling is `loud`, and a `page` sent to it arrives as a `loud`.

## The send

Form-encoded or JSON, both are the same call:

```js
await fetch(process.env.MAST_URL, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    title: "checkout",                      // ≤ 250 chars; which app or component
    body: String(err.message).slice(0, 4096),
    priority: "loud",                       // quiet | normal | loud | page
    url: "https://example.com/admin/orders", // optional tap target, http(s) only
    url_title: "Open orders",
    key: "checkout-500",                    // dedupe: repeats fold into one card
  }),
});
```

```bash
curl -fsS -X POST "$MAST_URL" -d title="backup" -d body="pg_dump exit 1" -d priority=loud
```

Rules that keep the pager useful:

- **Fire and forget.** Send after the request has already failed, off the response path
  (`ctx.waitUntil`, a background task, `after()`); a page must never make a failure slower.
- **Always set `key`** on anything that can fire in a loop. A handler that throws four hundred
  times pages once; the card counts up in place.
- **Priority is a promise.** `normal` for events (a signup, a deploy), `loud` for failures the
  owner should see soon, `page` only for "get up now": a charge failed, the site is down,
  data is being lost. `page` repeats until acknowledged and ignores quiet hours.
- Send at most a line of text. The owner reads it on a lock screen.
- A send answers `202 {"ok":true,"id":"mm_…","state":"queued"}` once stored. `muted` and
  `deduped` are also success. `404` is a wrong or rotated key; `429` is 60 sends a minute.

## Vitals: the job that stops running

An error handler cannot report the job that never ran. For anything scheduled, ask the owner
to create the channel as a **vital** with the job's period, and have the job send a heartbeat
only on success:

```cron
17 3 * * *  /usr/local/bin/backup.sh && curl -fsS "$MAST_URL" >/dev/null
```

```js
// at the end of the successful path, and nowhere else
await fetch(process.env.VITAL_URL, { method: "POST", body: new URLSearchParams({ body: `swept ${n} rows` }) });
```

If no beat arrives inside `period + grace`, Mast pages the owner. A job that knows it failed
says so and pages at once: `POST $MAST_URL/fail -d body="…"`. Text on a beat is proof of life
too, so a heartbeat can also say what the job did.

## Where to put the calls

- **Unhandled exceptions**: the outermost error boundary of the server or worker.
- **Payments**: the webhook handler on `payment_failed`, `dispute.created`, and any signature
  verification failure. Priority `page` for money leaving or charges failing.
- **Signups and orders**: `normal`, with `url` pointing at the admin view.
- **Scheduled work**: a vital per schedule, beat on success, `/fail` on a caught failure.
- **Deploys**: `normal` on success, `loud` on failure, from CI with the URL in a CI secret.

## Waiting for a human

A script can page and wait: the channel key can read its own messages.

```bash
id=$(curl -sS -X POST "$MAST_URL" -d title="promote 2026.09.010?" -d priority=page | jq -r .id)
until [ "$(curl -sS "$MAST_URL/messages/$id" | jq -r .state)" = "acked" ]; do sleep 10; done
```

Full field reference and limits: https://tissue.systems/docs/mast/connect/
