# Spec — App preview channel, controlled from wiom.tv

**Goal.** The channel shown in the customer-app's Wiom TV preview (unserviceable
screen, Option 3) is decided by **one editable place in the wiom.tv repo**, served
over an accessible API. Editing that one place changes both (a) what plays in the
app preview and (b) which channel wiom.tv lands on after the user taps through —
with **no app release** and **no second config to keep in sync**.

Single source of truth = wiom.tv. The app holds no channel list.

---

## 1. The contract

### `GET https://wiom.tv/tv/api/app-preview`

Public, unauthenticated, GET, JSON. (Same posture as `/tv/api/order`, already public.)

```json
{
  "primary":   { "ch": 2,  "name": "Dangal TV", "url": "https://live-dangal.akamaized.net/liveabr/playlist.m3u8" },
  "fallbacks": [
    { "ch": 40, "name": "NDTV India", "url": "https://…/master.m3u8" },
    { "ch": 24, "name": "…",          "url": "https://…/playlist.m3u8" }
  ],
  "landing_param": "ch",
  "updated_at": "2026-07-23T00:00:00Z"
}
```

- `primary` — the channel the app plays in the band.
- `fallbacks` — ordered; app tries these if `primary` fails to start (mirrors the
  prototype's Dangal → Dangal 2 → NDTV chain).
- `landing_param` — the query key the app appends when opening wiom.tv. Lets wiom.tv
  rename the param later without an app change. Value is `"ch"`.
- `updated_at` — for debugging/observability only.

**Caching.** `Cache-Control: public, max-age=300` (5 min). Repo edits propagate within
5 minutes; the hot path stays a cheap static read.

**CORS.** None required — the consumer is a **native** app (Dart `http`), not a browser.
(If a browser/PWA ever consumes it, add `Access-Control-Allow-Origin: *` — one line.)

---

## 2. The one place you edit in the repo

Three implementation options, smallest first. All satisfy "edit the repo → channel
changes." Pick one.

### Option A — inline in `server.js` (absolute minimum: 1 new route, no new file)

```js
// server.js — add near the other routes (after /api/experiment, before /dashboard).
// THIS BLOCK IS THE CONTROL SURFACE. Edit these channels to change the app preview.
app.get(`${BASE}/api/app-preview`, (req, res) => {
  res.set('Cache-Control', 'public, max-age=300');
  res.json({
    primary:   { ch: 2,  name: 'Dangal TV',  url: 'https://live-dangal.akamaized.net/liveabr/playlist.m3u8' },
    fallbacks: [
      { ch: 40, name: 'NDTV India', url: 'https://…/master.m3u8' },
      { ch: 24, name: '…',          url: 'https://…/playlist.m3u8' }
    ],
    landing_param: 'ch',
    updated_at: '2026-07-23T00:00:00Z'
  });
});
```

Changing the channel = editing this route + `reload-wiom-tv`. No new file, no refactor.
Cost: the 2–3 preview URLs are duplicated from the client channel list (they're stable
and fallback-protected, so low risk).

### Option B — small JSON file (nicer to edit, no code change to swap a channel)

`public/app-preview.json` holds the same object; the route just serves it:

```js
app.get(`${BASE}/api/app-preview`, (req, res) => {
  res.set('Cache-Control', 'public, max-age=300');
  res.sendFile(require('path').join(__dirname, 'public', 'app-preview.json'));
});
```

Changing the channel = edit one JSON file. (If served as a static file directly, even
the route is optional — but the explicit route keeps the URL stable and cache-controlled.)

### Option C — resolve from the canonical channel list (zero URL duplication)

The `channels` array (num→name→url) currently lives **inside `wiom-tv.html`** (client
only; `server.js` has no channel URLs — `/api/order` returns bare numbers). To let the
endpoint return URLs without duplicating them, extract the array into a shared
`channels.json` that both `server.js` and the client load, then:

```js
const CHANNELS = require('./channels.json');
const byNum = Object.fromEntries(CHANNELS.map(c => [c.ch, c]));
const APP_PREVIEW_CHS = [2, 40, 24];          // <-- edit this line to change the channel
app.get(`${BASE}/api/app-preview`, (req, res) => {
  const pick = n => { const c = byNum[n]; return c && { ch: c.ch, name: c.name, url: c.url }; };
  const [p, ...f] = APP_PREVIEW_CHS.map(pick).filter(Boolean);
  res.set('Cache-Control', 'public, max-age=300');
  res.json({ primary: p, fallbacks: f, landing_param: 'ch' });
});
```

Editing the channel = change one array of numbers; URLs come from the single canonical
list, so they can never drift. Cost: a real (small) refactor of how the client loads its
channel array.

**Recommendation:** ship **Option A** now (smallest, satisfies the requirement today),
migrate to **Option C** whenever the channel list is next touched anyway. Option B is a
fine middle ground if edits will be frequent.

---

## 3. Landing continuity (the tap)

The app opens: `https://wiom.tv/?<landing_param>=<primary.ch>&src=app_unserviceable`
e.g. `https://wiom.tv/?ch=2&src=app_unserviceable`

wiom.tv must honour `?ch=`. **3-line change, against the LIVE file**
(`/home/ubuntu/wiom-tv/public/wiom-tv.html`, verified 2026-07-23):

```js
// 1) read it once — near line 827 (where _arm is already read)
const _forceCh = parseInt(new URLSearchParams(location.search).get('ch'), 10) || null;

// 2) _boot() prefers it — line 1338
-  const last = parseInt(localStorage.getItem('wiom-tv-last'), 10) || (channels[0] && channels[0].ch) || 1;
+  const last = _forceCh || parseInt(localStorage.getItem('wiom-tv-last'), 10) || (channels[0] && channels[0].ch) || 1;

// 3) a forced channel skips fse_v2 enrolment — line 1395
-  if (_needsEnrolment) {
+  if (_needsEnrolment && !_forceCh) {
```

Why line 3: app referrals are new uids, and new uids currently go down `_landingBoot()`
(the experiment's genre hero) instead of `_boot()`. Guarding on `_forceCh` sends them to
`_boot()` → the forced channel. **Side benefit:** it also cleanly **excludes app traffic
from fse_v2** — they never enrol, never get stamped, so they can't pollute the
first-impression-hold signal that computes `heroByGenre`. The code already treats
non-enrolment as valid ("Failure mode is exclusion, never corruption").

`src=app_unserviceable` needs **no** wiom.tv change — `entry_params` (live, line 1105)
already sweeps every URL param into the analytics payload, queryable in `analytics.db`.

**Edge case for Satyam's call:** a `ch` not in the list → `findIndex` returns −1 →
`tuneFn(0)` (wrong channel, not a crash). Falling back to normal `_boot()` instead is one
extra line and strictly better.

---

## 4. App side (customer-app, Flutter, release/sprint-18)

On the unserviceable screen (Option 3 band):

1. `GET https://wiom.tv/tv/api/app-preview` (short timeout, e.g. 3s).
2. Play `primary.url` in the framed preview. On start-failure, walk `fallbacks` in order.
3. Tap the band → open `https://wiom.tv/?{landing_param}={primary.ch}&src=app_unserviceable`
   via `Utility.launchUrl`.
4. **Never empty:** if the fetch fails or every stream fails, keep the local poster
   (channel-grid still frame) — same rule as the prototype. Ship a hardcoded last-resort
   `primary` in the app as the final fallback so the band always has something to attempt.

No channel list in the app. `video_player` (already a dep) plays HLS. Native → no CORS,
no autoplay-policy gymnastics. Optional: cache the last good response locally so a failed
fetch still shows the previously-chosen channel.

---

## 5. What each side owns

| Concern | Owner | Change to move the channel |
|---|---|---|
| Which channel the app previews | **wiom.tv repo** (§2) | Edit one place + `reload-wiom-tv` |
| Which channel wiom.tv lands on | **wiom.tv** `?ch=` (§3) | Automatic — app sends `primary.ch` |
| Playing the stream / UX | customer-app | — |
| Attribution (`src=app_unserviceable`) | wiom.tv analytics | None (already captured) |

One edit on wiom.tv changes both the preview and the landing. The app ships once and
never needs a release to change the channel.

---

## 6. The ask to Satyam (minimum)

1. Add `GET /tv/api/app-preview` — Option A block above (1 route). *(~10 lines)*
2. Honour `?ch=` in `_boot()` + skip fse_v2 when present. *(3 lines)*
3. Confirm treatment of `src=app_unserviceable` traffic in fse_v2 (excluded by #2; just
   needs acknowledgement). *(no code)*

No new dependency, no auth, no CORS, no change to ranking/tuning/landing for existing users.

---

## 7. Future (not v1)

- **Auto-pick from live data:** `/api/app-preview` could compute `primary` from
  `/api/order`'s `heroByGenre` (best cold performer) instead of an editorial pick.
  Deferred — v1 is a deliberate, stable choice; auto mode reintroduces cold-start and
  experiment-coupling questions.
- **Per-context previews:** the endpoint could branch on a `?ctx=` param (unserviceable
  vs payment-success vs …) so different app surfaces preview different channels.
