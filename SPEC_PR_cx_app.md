# PR spec — customer-app: Wiom TV preview on the unserviceable screen

**Repo:** `wiom-tech/customer-app` (Flutter, package `wiom_gold`)
**Base branch:** `release/sprint-18` (the live line; `master` is stale)
**Depends on:** nothing. Ships and works standalone; upgrades itself when the
wiom.tv PR (`SPEC_PR_wiom_tv.md`) lands. See §6.

---

## 1. Scope

On the location-unserviceable screen, add a bottom "व्योम TV" band (Option 3):
a framed, live wiom.tv channel playing muted, over a local poster, with a
"फ्री में देखना शुरू करें" CTA. Tapping opens wiom.tv on the same channel.

Target screen (verified on sprint-18):
`lib/new_app/presentation/pages/booking/location_unserviceable/location_unserviceable_screen.dart`
— a `StandardWidget` with `content:` (240px SVG + address pill) and
`primaryButton:` slots. Copy keys `LOCATION_UNSERVICEABLE_*` live in
`assets/language/new_language_data.json`.

Prototype (approved reference): https://shivanksood-prog.github.io/wiom-tv-unserviceable-entry/ → Option 3

---

## 2. The band is a parametrised widget

`WiomTvPreviewBand(BandConfig config)` — the screen never hardcodes a channel.

```dart
class BandConfig {
  final PreviewChannel primary;          // {ch, name, url}
  final List<PreviewChannel> fallbacks;  // tried in order on start-failure
  final String landingParam;             // query key for the tap-through, default "ch"
  final int entryDelayMs;                // slide-in delay, DEFAULT 300
  final int capSeconds;                  // auto-stop, default 25
}
```

`primary/fallbacks/landingParam/entryDelayMs` are all **injected**, so behaviour is
tunable from wiom.tv without an app change (§6).

---

## 3. Config resolution (graceful — works with NO wiom.tv change)

```
1. Start from a baked-in DEFAULT_CONFIG shipped in the app:
     primary   = { ch: 2, name: "Dangal TV", url: "<dangal m3u8>" }
     fallbacks = [ NDTV India, … ]        // 2–3 stable streams
     landingParam = "ch"
     entryDelayMs = 300
     capSeconds   = 25
2. GET <wiom.tv>/tv/api/app-preview   (timeout ~3s)
     200 + valid JSON → overlay onto DEFAULT_CONFIG (any field the payload provides
                         wins; missing fields keep the default)
     404 / timeout / invalid → keep DEFAULT_CONFIG, carry on
3. (optional) cache the last good response so a later failed fetch still shows the
   previously-chosen channel.
```

Endpoint URL as a `StringConstants` value. Native `http`/`dio` → **no CORS** (CORS
is browser-only). `firebase_remote_config` is already a dep if you prefer to source
the endpoint base or a kill-switch from RC — not required.

---

## 4. Band behaviour (matches the approved prototype)

**Layout — reserve first, animate second (this is what keeps the CTA safe):**
- The band sits at the bottom. **Reserve its exact height in the layout at first
  paint** so the primary CTA and login link are placed in their final positions and
  **never move**.
- If `entryDelayMs > 0`, start the band translated **below** its reserved slot and
  slide it up (transform/offset only) into that already-empty slot after the delay.
  Because the slot is below the CTA and the motion is transform-only, the band can
  neither reflow layout nor cover the CTA — at any delay. `entryDelayMs == 0` →
  present at first paint, no motion.
- **Default `entryDelayMs = 300`**: the slide completes before the user's reach for
  the CTA (~1.2s), so it reads as the screen coming to life, not as something
  arriving over their decision. Verified in the prototype: CTA top constant while
  the band travels its full slide.

**Preview — never empty, data-bounded:**
- Render a **local poster** (channel-grid still frame) at t=0. Play `primary.url`
  (`video_player`, HLS) and **fade the video in over the poster** once it decodes a
  frame — the poster never disappears, so a failed stream is a finished-looking
  surface, never a black box or spinner.
- On start-failure, walk `fallbacks` in order. If all fail, hold the poster.
- Autoplay **muted**, lowest variant. **Auto-stop at `capSeconds` (25)** → poster +
  tap-to-replay. Bounds data for users who by definition have no Wiom net.
- "LIVE" badge shows **only** while a stream is actually playing, never over the poster.

**Short viewports:** below ~720px logical height, drop the decorative 240px graphic
(not the video) so the CTA is never pushed behind the band. Keep the preview large —
it is the reason this option exists.

**Tap:** whole band → `Utility.launchUrl(
"<wiom.tv>/?${config.landingParam}=${config.primary.ch}&src=app_unserviceable")`.

---

## 5. Deps, tokens, analytics

- **Deps:** `video_player: ^2.3.14` already present on sprint-18 → **zero new deps**.
  (No `webview_flutter` / `audioplayers` on sprint-18 — do not reach for them.)
- **Tokens:** `WiomColors`, `WiomTypography`, `WiomSpacing`, `WiomScaling`
  (design size 360×640). Dark band = `neutral900`.
- **Copy:** add band keys (badge / breadth line / genres / CTA) to
  `new_language_data.json` for hi / en / mr.
- **Analytics:** `new_app/core/analytics` — log band shown, play started, cap
  reached, replay, tap-through (with the channel + `src`). Put a per-variant UTM on
  the wiom.tv URL if bounce attribution is wanted beyond `src`.

---

## 6. Degradation matrix (why this PR is independent)

| wiom.tv endpoint | wiom.tv `?ch=` | Band shows | Landing channel |
|---|---|---|---|
| ❌ not built | ❌ not built | baked-in default (any channel) | wiom.tv default *(differs — acceptable)* |
| ✅ built | ❌ not built | curated channel | wiom.tv default *(differs — acceptable)* |
| ✅ built | ✅ built | curated channel | **same channel** ✓ |

`?ch=` is currently **inert** on live wiom.tv (read nowhere; only swept into
analytics), so sending it today causes no error. This PR can merge and ship before
the wiom.tv PR; it upgrades automatically once that lands. No app re-release needed
to change the channel or the entry timing afterwards.

---

## 7. Known platform deltas from the prototype (agree before build)

1. **Bottom edge:** `StandardWidget`'s bottom inset is hardcoded (`spacing16`, no
   param), so the band floats ~16px above the screen edge — the prototype is flush.
   Options: accept the gap / add a param (28 screens use `StandardWidget`) / fork the
   layout for this screen. **Decide first.**
2. **Scroll:** `StandardWidget` body is `SingleChildScrollView` + `Center`; the
   prototype uses fixed `dvh` math. Diverges on short devices — the §4 "drop the
   graphic" rule is the mitigation.
3. **Text metrics:** Hindi in NotoSansDisplay ≠ browser; match type *tokens*, accept
   ±few px, don't chase pixel parity.

---

## 8. Files touched (estimate)

- new: `…/location_unserviceable/widgets/wiom_tv_preview_band.dart`
- new: `…/data/band_config.dart` (model + DEFAULT_CONFIG + resolve)
- edit: `location_unserviceable_screen.dart` (mount band, reserve slot)
- edit: `assets/language/new_language_data.json` (hi/en/mr keys)
- edit: `StringConstants` (endpoint URL, wiom.tv base)
- edit: analytics enum/event

No compile on this box (no Flutter SDK) — `flutter analyze` + on-device visual check
required; `.github/workflows/build-apk.yml` builds an APK on the PR.
