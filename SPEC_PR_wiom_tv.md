# PR spec — wiom.tv: app-preview endpoint + `?ch=` landing

**Repo:** wiom.tv (`june-wiom-tv`). Live files verified on the server 2026-07-23:
`/home/ubuntu/wiom-tv/public/wiom-tv.html`, `/home/ubuntu/wiom-tv/server.js`.
**Depends on:** nothing. Ships independently; the customer-app PR
(`SPEC_PR_cx_app.md`) consumes it but works without it.

Two changes, both small. No new dependency, no auth, no CORS, nothing changed for
existing wiom.tv users.

---

## 1. New endpoint — the app's control surface

### `GET /tv/api/app-preview`

Public, unauthenticated, JSON (same posture as `/tv/api/order`). Add near the other
routes (`server.js`: `/api/experiment` is at line 468, `/dashboard` at 530 — put it
between). **This block is the one place edited to change the app preview.**

```js
// server.js — customer-app unserviceable-screen preview. Edit to change what the app plays.
app.get(`${BASE}/api/app-preview`, (req, res) => {
  res.set('Cache-Control', 'public, max-age=300');   // repo edits propagate within 5 min
  res.json({
    primary:   { ch: 2,  name: 'Dangal TV',   url: 'https://live-dangal.akamaized.net/liveabr/playlist.m3u8' },
    fallbacks: [
      { ch: 40, name: 'NDTV India', url: 'https://…/master.m3u8' },
      { ch: 24, name: '…',          url: 'https://…/playlist.m3u8' }
    ],
    landing_param: 'ch',
    entry: { delayMs: 300 },          // band slide-in delay; app default is also 300
    updated_at: '2026-07-23T00:00:00Z'
  });
});
```

- `primary` / `fallbacks` — channel(s) the app plays (`{ch, name, url}`; `url` is the
  HLS playlist, same as the `channels` array in `wiom-tv.html`).
- `landing_param` — query key the app appends on tap. Value `"ch"` (matches §2).
- `entry.delayMs` — **optional** band entry timing; lets you tune early-vs-late (or
  A/B it) without an app release. App default is 300 if omitted.
- `Cache-Control: max-age=300` — cheap hot path; edits go live in ≤5 min after reload.
- **CORS:** none needed — the consumer is a native app, not a browser. (Add
  `Access-Control-Allow-Origin: *` only if a browser/PWA ever consumes it.)

**Variants (optional, pick when implementing):**
- **A — inline (above):** smallest, 1 route. Edit the route + `reload-wiom-tv` to
  change the channel. Preview URLs duplicated from the channel list (stable, low risk).
- **C — resolve from the channel list:** extract the `channels` array into a shared
  `channels.json`, keep only `const APP_PREVIEW_CHS = [2, 40, 24]` and resolve
  numbers→urls at serve time (zero URL drift). More work; do it when the channel
  array is next touched. Recommend **A now**, C later.

---

## 2. Honour `?ch=` on landing — 3 lines

App opens `wiom.tv/?ch=<primary.ch>&src=app_unserviceable`. Make `_boot()` respect it.
Live line numbers in `public/wiom-tv.html` (verified 2026-07-23):

```js
// 1) read it once — near line 827, where _arm is already read
const _forceCh = parseInt(new URLSearchParams(location.search).get('ch'), 10) || null;

// 2) _boot() prefers it — line 1338
-  const last = parseInt(localStorage.getItem('wiom-tv-last'), 10) || (channels[0] && channels[0].ch) || 1;
+  const last = _forceCh || parseInt(localStorage.getItem('wiom-tv-last'), 10) || (channels[0] && channels[0].ch) || 1;

// 3) a forced channel skips fse_v2 enrolment — line 1395
-  if (_needsEnrolment) {
+  if (_needsEnrolment && !_forceCh) {
```

**Why line 3:** app referrals are new uids, and new uids currently go down
`_landingBoot()` (the experiment's genre hero) instead of `_boot()`. Guarding on
`_forceCh` routes them to `_boot()` → the forced channel.

**Side benefit — clean fse_v2 exclusion.** App-referred users never enrol, never get
stamped, so they cannot pollute the first-impression-hold signal that computes
`heroByGenre`. They arrive pre-warmed by up to 25s in the app band, i.e. not cold —
exactly the contamination the guide signal already guards against ("a boot is not a
choice"). The code already treats non-enrolment as valid: *"Failure mode is
exclusion, never corruption."*

**Edge case (your call):** a `ch` not in `channels` → `findIndex` returns −1 →
`tuneFn(0)` (wrong channel, not a crash). Falling back to normal `_boot()` instead is
one extra line and strictly better.

---

## 3. `src=app_unserviceable` — already handled

No change. `entry_params` (live, `wiom-tv.html` line 1105) already sweeps every URL
param into the analytics payload, so `src` lands in `analytics.db` and is queryable
the moment the app starts sending it. Use it to segment/report app-referred traffic.

---

## 4. The ask, minimal

1. Add `GET /tv/api/app-preview` (§1, variant A). *(~12 lines)*
2. Honour `?ch=` in `_boot()` + skip fse_v2 when present (§2). *(3 lines)*
3. Confirm treatment of `src=app_unserviceable` in fse_v2 readouts — excluded by #2,
   just needs acknowledgement. *(no code)*

**Rollout:** merge + `reload-wiom-tv` → live in minutes. Independent of the app PR;
once both are in, the app lands users on the same channel it previewed, and you can
change that channel any day by editing the endpoint — no app release.

⚠ Confirm the §2 line numbers against the live file before applying (it was last
modified Jul 13; a later edit could shift them).
