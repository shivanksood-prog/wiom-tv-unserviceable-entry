import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Wiom design tokens (from CLAUDE.md design system)
// ─────────────────────────────────────────────────────────────────────────────
class Wiom {
  static const brand600 = Color(0xFFD9008D);
  static const brand100 = Color(0xFFFFE5F6);
  static const brand300 = Color(0xFFFFB2E4);
  static const neutral900 = Color(0xFF161021);
  static const neutral700 = Color(0xFF665E75);
  static const neutral500 = Color(0xFFA7A1B2);
  static const neutral300 = Color(0xFFD7D3E0);
  static const neutral200 = Color(0xFFE7E3EF);
  static const neutral100 = Color(0xFFF1EDF7);
  static const white = Color(0xFFFAF9FC);
  static const text = Color(0xFF161021);
  static const negative600 = Color(0xFFE01E00);
  static const font = 'NotoSansDevanagari';
}

// ─────────────────────────────────────────────────────────────────────────────
// BandConfig — everything about the preview is injected (SPEC_PR_cx_app §2)
// ─────────────────────────────────────────────────────────────────────────────
class PreviewChannel {
  final int ch;
  final String name;
  final String url; // HLS on device; MP4 asset stand-in on web
  const PreviewChannel(this.ch, this.name, this.url);
}

class BandConfig {
  final PreviewChannel primary;
  final List<PreviewChannel> fallbacks;
  final String landingParam;
  final int entryDelayMs; // DEFAULT 300
  final int capSeconds;   // DEFAULT 25
  const BandConfig({
    required this.primary,
    this.fallbacks = const [],
    this.landingParam = 'ch',
    this.entryDelayMs = 300,
    this.capSeconds = 25,
  });
}

// The baked-in default the app ships with (works with NO wiom.tv change).
// On web the plugin can't play HLS in Chrome, so we point at an MP4 asset to
// prove the player + layout; on a device this URL would be the live .m3u8.
const kDefaultConfig = BandConfig(
  primary: PreviewChannel(2, 'Dangal TV', 'asset:///assets/video/preview.mp4'),
  fallbacks: [],
  entryDelayMs: 300,
  capSeconds: 25,
);

void main() => runApp(const ProtoApp());

class ProtoApp extends StatelessWidget {
  const ProtoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: Wiom.font, scaffoldBackgroundColor: Wiom.white),
      home: const LocationUnserviceableScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Faithful copy of the live StandardWidget host (content + primaryButton slots)
// with the TV band mounted at the bottom.
// ─────────────────────────────────────────────────────────────────────────────
class LocationUnserviceableScreen extends StatelessWidget {
  const LocationUnserviceableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.of(context).size.height <= 720;
    return Scaffold(
      backgroundColor: Wiom.white,
      body: SafeArea(
        // Column, NOT Stack: the band is a sibling that takes its own height, so its
        // slot is RESERVED from first frame and the Expanded scroll area gets the rest.
        // AnimatedSlide then translates the band into its reserved slot — it can never
        // cover the CTA above it. (A naive bottom overlay hides the CTA — proven at 780px.)
        child: Column(
          children: [
            // ── zone 1: the production screen content, unchanged ──────────────
            Expanded(
              child: SingleChildScrollView(
              // Condensed zone 1: the band takes a large chunk, so the production 240px
              // graphic is scaled down (and dropped below 720px) — the message stays #1 and
              // the CTA stays above the band. Mirrors the web prototype's fold rules.
              padding: EdgeInsets.fromLTRB(16, short ? 12 : 20, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!short)
                    SizedBox(
                      height: 118,
                      width: 118,
                      child: SvgPicture.asset(
                          'assets/svg/location_unserviceable_graphic.svg',
                          fit: BoxFit.contain),
                    ),
                  SizedBox(height: short ? 4 : 10),
                  const Text('हम अभी आपके इलाके में उपलब्ध नहीं हैं',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: Wiom.text)),
                  const SizedBox(height: 12),
                  _addressPill(),
                  const SizedBox(height: 14),
                  _priButton('ये मेरे इलाके की लोकेशन नहीं है'),
                  const SizedBox(height: 12),
                  Text.rich(TextSpan(children: const [
                    TextSpan(
                        text: 'पहले से व्योम लगा हुआ है ',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Wiom.text)),
                    TextSpan(
                        text: '›',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Wiom.brand600)),
                  ])),
                ],
              ),
              ),
            ),
            // ── the parametrised band: a sibling, so its slot is reserved ─────
            const WiomTvPreviewBand(config: kDefaultConfig),
          ],
        ),
      ),
    );
  }

  static Widget _addressPill() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Wiom.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Wiom.neutral200),
        ),
        child: Row(children: const [
          Icon(Icons.location_on, color: Wiom.neutral500, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rajouri Garden',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: Wiom.text)),
              SizedBox(height: 2),
              Text('Rajouri Garden, New Delhi, Delhi 110027, India',
                  style: TextStyle(fontSize: 13, color: Wiom.neutral700)),
            ]),
          ),
        ]),
      );

  static Widget _priButton(String label) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: Wiom.brand600,
            foregroundColor: Wiom.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// WiomTvPreviewBand — reserved slot + slide, poster, HLS/asset player, 25s cap
// ─────────────────────────────────────────────────────────────────────────────
class WiomTvPreviewBand extends StatefulWidget {
  final BandConfig config;
  const WiomTvPreviewBand({super.key, required this.config});
  @override
  State<WiomTvPreviewBand> createState() => _WiomTvPreviewBandState();
}

class _WiomTvPreviewBandState extends State<WiomTvPreviewBand>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _vc;
  bool _playing = false; // stream decoded a frame → fade video in over poster
  bool _ended = false;   // 25s cap reached → poster + replay
  bool _slidIn = false;  // entry animation state
  Timer? _cap;
  int _fallbackIdx = -1;

  @override
  void initState() {
    super.initState();
    // present-at-first-paint vs slide-in — the CTA is never affected either way
    // because the band sits in its own bottom slot (Align bottomCenter).
    if (widget.config.entryDelayMs > 0) {
      _slidIn = false;
      Timer(Duration(milliseconds: widget.config.entryDelayMs),
          () => mounted ? setState(() => _slidIn = true) : null);
    } else {
      _slidIn = true;
    }
    _start(widget.config.primary);
  }

  void _start(PreviewChannel c) {
    _vc?.dispose();
    final uri = c.url.startsWith('asset:')
        ? null
        : Uri.parse(c.url);
    _vc = uri == null
        ? VideoPlayerController.asset('assets/video/preview.mp4')
        : VideoPlayerController.networkUrl(uri);
    _vc!
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        _vc!.play();
        setState(() => _playing = true);
        _cap?.cancel();
        _cap = Timer(Duration(seconds: widget.config.capSeconds), () {
          if (!mounted) return;
          _vc?.pause();
          setState(() { _playing = false; _ended = true; });
        });
      }).catchError((Object _) { _tryFallback(); });
  }

  void _tryFallback() {
    _fallbackIdx++;
    if (_fallbackIdx < widget.config.fallbacks.length) {
      _start(widget.config.fallbacks[_fallbackIdx]);
    } // else: poster holds — never a black box
  }

  void _replay() {
    setState(() { _ended = false; _fallbackIdx = -1; });
    _start(widget.config.primary);
  }

  @override
  void dispose() { _cap?.cancel(); _vc?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.of(context).size.height <= 720;
    // The slide: band starts translated fully below its own height, then to 0.
    // It lives in the bottom slot, so this never touches the CTA above it.
    return AnimatedSlide(
      offset: _slidIn ? Offset.zero : const Offset(0, 1.1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Wiom.neutral900,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(color: Color(0x59161021), blurRadius: 34, offset: Offset(0, -12)),
          ],
        ),
        padding: EdgeInsets.fromLTRB(16, short ? 10 : 13, 16, 16),
        child: GestureDetector(
          onTap: () {}, // → Utility.launchUrl(wiom.tv/?ch=..&src=app_unserviceable)
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('तब तक के लिए',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: Wiom.brand300)),
              const SizedBox(height: 3),
              Row(children: [
                const Text('व्योम TV',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: Wiom.white)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Wiom.brand100, borderRadius: BorderRadius.circular(999)),
                  child: const Text('🎁 100% फ्री',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w700, color: Wiom.brand600)),
                ),
              ]),
              const SizedBox(height: 10),
              _screen(short),
              if (!short) ...[
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                  Text('ढेरों लाइव चैनल',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: Wiom.white)),
                  SizedBox(width: 7),
                  Flexible(
                    child: Text('न्यूज़ • मूवी • भक्ति • मनोरंजन • खेल',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: Wiom.neutral500)),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Wiom.brand600,
                    foregroundColor: Wiom.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('फ्री में देखना शुरू करें',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // The framed preview: local poster always present; video fades in over it.
  Widget _screen(bool short) {
    final w = _vc;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF4A4157), width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(fit: StackFit.expand, children: [
            _poster(),
            AnimatedOpacity(
              opacity: _playing ? 1 : 0,
              duration: const Duration(milliseconds: 450),
              child: (w != null && w.value.isInitialized)
                  ? FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                          width: w.value.size.width,
                          height: w.value.size.height,
                          child: VideoPlayer(w)),
                    )
                  : const SizedBox.shrink(),
            ),
            if (_playing)
              Positioned(
                top: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0x99000000), borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    _Dot(), SizedBox(width: 4),
                    Text('LIVE',
                        style: TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            if (_ended)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: const Color(0x9E000000), borderRadius: BorderRadius.circular(999)),
                  child: GestureDetector(
                    onTap: _replay,
                    child: const Text('▶ फिर से देखें',
                        style: TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  // Local channel-grid poster — the band is never empty, never a black box.
  Widget _poster() => Container(
        color: const Color(0xFF0D0916),
        padding: const EdgeInsets.all(3),
        child: GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.4,
          children: List.generate(6, (i) {
            const grads = [
              [Color(0xFF2A2336), Color(0xFF3B3348)],
              [Color(0xFF3A2440), Color(0xFF4A2F52)],
              [Color(0xFF2A2336), Color(0xFF3B3348)],
              [Color(0xFF24303F), Color(0xFF2F3F52)],
              [Color(0xFF2A2336), Color(0xFF3B3348)],
              [Color(0xFF3F2A24), Color(0xFF52382F)],
            ];
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: grads[i]),
              ),
            );
          }),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
      width: 6, height: 6,
      decoration:
          const BoxDecoration(color: Wiom.negative600, shape: BoxShape.circle));
}
