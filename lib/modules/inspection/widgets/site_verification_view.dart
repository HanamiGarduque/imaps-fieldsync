import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/quick_actions_sheet.dart' show MapDetailPanel;
import '../../../core/widgets/field_form_widgets.dart';
import 'inspection_step_header.dart';

/// Step 1 presentation only. GPS, road geometry, cache and progression remain
/// owned by SiteMapScreen; Quick Action Map uses its existing shared panel.
class SiteVerificationView extends StatefulWidget {
  const SiteVerificationView({
    super.key,
    required this.mapBuilder,
    required this.location,
    required this.ready,
    required this.hasDeviceLocation,
    required this.retryingLocation,
    required this.hasRoute,
    required this.routeFromCache,
    required this.nearSite,
    required this.rework,
    required this.onBack,
    required this.onRetryLocation,
    required this.onFit,
    required this.onProceed,
    this.distanceMeters,
    this.routeDistanceMeters,
    this.routeDurationSeconds,
    this.approachNotice = false,
    this.gpsReliable = false,
    this.hasDirectLinks = false,
    this.routeEstimateStale = false,
  });

  final Widget Function(EdgeInsets padding) mapBuilder;
  final String location;
  final bool ready;
  final bool hasDeviceLocation;
  final bool retryingLocation;
  final bool hasRoute;
  final bool routeFromCache;
  final bool nearSite;
  final bool rework;
  final double? distanceMeters;
  final double? routeDistanceMeters;
  final double? routeDurationSeconds;
  final bool approachNotice;
  final bool gpsReliable;
  final bool hasDirectLinks;
  final bool routeEstimateStale;
  final VoidCallback onBack;
  final VoidCallback onRetryLocation;
  final VoidCallback onFit;
  final VoidCallback onProceed;

  @override
  State<SiteVerificationView> createState() => _SiteVerificationViewState();
}

class _SiteVerificationViewState extends State<SiteVerificationView> {
  bool _fullscreen = false;
  bool _collapsed = false;
  bool _initialFitApplied = false;
  final _headerKey = GlobalKey();
  final _panelKey = GlobalKey();
  final _attributionKey = GlobalKey();
  final _detailsHeaderKey = GlobalKey();
  final _actionKey = GlobalKey();
  double _headerHeight = 156;
  double _panelHeight = 260;
  double _attributionHeight = 42;
  double _detailsHeaderHeight = 48;
  double _actionHeight = 52;
  static const _motion = Duration(milliseconds: 220);

  Size _textSize(
    String text,
    TextStyle style, {
    double width = double.infinity,
  }) {
    final measure = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1.0, width));
    final size = measure.size;
    measure.dispose();
    return size;
  }

  void _measureOverlays(Size mapSize, EdgeInsets fitPadding) {
    if (!mounted) return;
    // Immersive landscape (matching GPS Verification) drops the header
    // entirely, so its measured height must not keep a stale portrait value.
    final immersive = _fullscreen || context.responsive.isLandscape;
    final header = immersive
        ? 0.0
        : (_headerKey.currentContext?.size?.height ?? _headerHeight);
    final panel = _panelKey.currentContext?.size?.height ?? _panelHeight;
    final attribution =
        _attributionKey.currentContext?.size?.height ?? _attributionHeight;
    final detailsHeader =
        _detailsHeaderKey.currentContext?.size?.height ?? _detailsHeaderHeight;
    final action = _actionKey.currentContext?.size?.height ?? _actionHeight;
    if ((header - _headerHeight).abs() < 0.5 &&
        (panel - _panelHeight).abs() < 0.5 &&
        (attribution - _attributionHeight).abs() < 0.5 &&
        (detailsHeader - _detailsHeaderHeight).abs() < 0.5 &&
        (action - _actionHeight).abs() < 0.5) {
      // initialCameraFit runs before these overlays are measured. Repair that
      // startup fit once, without resetting later map gestures or disclosure.
      if (widget.ready &&
          !_initialFitApplied &&
          mapSize.width > fitPadding.horizontal &&
          mapSize.height > fitPadding.vertical) {
        _initialFitApplied = true;
        widget.onFit();
      }
      return;
    }
    setState(() {
      _headerHeight = header;
      _panelHeight = panel;
      _attributionHeight = attribution;
      _detailsHeaderHeight = detailsHeader;
      _actionHeight = action;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.responsive;
    final safe = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth - safe.horizontal;
        final height = box.maxHeight - safe.vertical;
        final landscape = bp.isLandscape;
        final headerHeight = _fullscreen || landscape ? 0.0 : _headerHeight;
        final split = landscape && !_fullscreen && !_collapsed && widget.ready;
        final sideWidth = (width * 0.34).clamp(260.0, 336.0);
        final mapRight = split ? safe.right + sideWidth + 24 : 0.0;
        // Measure these wrapping labels before the FIRST layout/rotation. The
        // previous viewport's measured heights can be too small for a pinned CTA.
        final innerWidth =
            (split ? sideWidth : math.min(520.0, width - 32)) - 26;
        final buttonStyle = Theme.of(context).textTheme.labelLarge!;
        final hideStyle = buttonStyle.merge(InsightTheme.inter(12));
        final hideWidth = math.max(
          48.0,
          _textSize(_collapsed ? 'Show' : 'Hide', hideStyle).width + 38,
        );
        final headerMinimum = math
            .max(
              48.0,
              math.max(
                _textSize(
                  'Site details',
                  DefaultTextStyle.of(
                    context,
                  ).style.merge(InsightTheme.urbanist(14)),
                  width: innerWidth - hideWidth,
                ).height,
                _textSize('Hide', hideStyle).height + 16,
              ),
            )
            .ceilToDouble();
        final actionMinimum = math
            .max(
              52.0,
              _textSize(
                    widget.rework ? 'Save' : 'Proceed to Location',
                    buttonStyle.merge(
                      InsightTheme.inter(14, w: FontWeight.w600),
                    ),
                    width: innerWidth - 58,
                  ).height +
                  28,
            )
            .ceilToDouble();
        // Measured content covers nonlinear font scaling and wrapped actions.
        // Reserve a readable scroll line as well as the pinned primary action.
        final panelMinHeight =
            math.max(_detailsHeaderHeight, headerMinimum) +
            math.max(_actionHeight, actionMinimum) +
            8 +
            12 +
            2 +
            MediaQuery.textScalerOf(context).scale(12) * 1.6;
        final horizontalControls =
            landscape ||
            (!_fullscreen &&
                height <
                    headerHeight + panelMinHeight + _attributionHeight + 144);
        final controlsHeight = horizontalControls ? 48.0 : 104.0;
        // The established header is unchanged. Very large text on a short phone
        // scrolls its two context containers rather than hiding either of them.
        final headerMaxHeight = landscape
            ? math.max(80.0, height - _attributionHeight - 144)
            : math.max(
                48.0,
                math.min(
                  height * 0.4,
                  height -
                      _attributionHeight -
                      controlsHeight -
                      panelMinHeight -
                      40,
                ),
              );
        final panelMaxHeight = landscape
            ? height - 32
            : math.max(
                panelMinHeight,
                math.min(
                  (widget.approachNotice || widget.nearSite ? 240 : 216) *
                      MediaQuery.textScalerOf(context).scale(12) /
                      12,
                  // Reserve both full targets, three 8dp gaps and 16dp bottom.
                  height -
                      headerHeight -
                      _attributionHeight -
                      controlsHeight -
                      40,
                ),
              );
        final panelBottom = safe.bottom + 16;
        final panelSpace = !_fullscreen && widget.ready
            ? (split ? 0.0 : _panelHeight + 8)
            : 0.0;
        final attributionBottom = panelBottom + panelSpace;
        final controlsTop = math.max(
          safe.top + (_fullscreen || landscape ? 8 : headerHeight + 8),
          box.maxHeight -
              attributionBottom -
              _attributionHeight -
              controlsHeight -
              8,
        );
        final fitPadding = EdgeInsets.fromLTRB(
          safe.left + 48,
          safe.top + (_fullscreen || landscape ? 48 : headerHeight + 24),
          (split ? mapRight : safe.right) +
              _textSize(
                'Target site',
                InsightTheme.inter(12, w: FontWeight.w600),
              ).width +
              // 22dp marker offset + 22dp padded label border + 64dp control
              // lane + 8dp clearance, including nonlinear/enlarged text.
              116,
          safe.bottom + panelSpace + _attributionHeight + 32,
        );
        WidgetsBinding.instance.addPostFrameCallback(
          (_) =>
              _measureOverlays(Size(box.maxWidth, box.maxHeight), fitPadding),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // The same element/controller survives disclosure, fullscreen and
            // rotation. The map also fills unused space beneath the side pane.
            Positioned.fill(child: widget.mapBuilder(fitPadding)),
            if (!_fullscreen && !landscape)
              Positioned(
                top: safe.top,
                left: safe.left,
                right: split ? mapRight : safe.right,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: headerMaxHeight),
                  child: SingleChildScrollView(
                    key: _headerKey,
                    child: InspectionStepHeader(
                      title: 'Site Verification',
                      subtitle: widget.location,
                      stepNumber: 1,
                      stepSubtitle: 'LOCATE TARGET',
                      compact: false,
                      onBack: widget.onBack,
                    ),
                  ),
                ),
              ),
            if (!_fullscreen && landscape)
              Positioned(
                left: safe.left + 12,
                top: safe.top + 12,
                child: FieldBackButton(
                  tooltip: 'Exit inspection',
                  onPressed: widget.onBack,
                ),
              ),
            if (widget.ready) ...[
              AnimatedPositioned(
                duration: _motion,
                curve: Curves.easeOutCubic,
                top: controlsTop,
                left: landscape ? safe.left + 16 : null,
                right: landscape ? null : safe.right + 16,
                child: Flex(
                  direction: horizontalControls
                      ? Axis.horizontal
                      : Axis.vertical,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapControl(
                      label: _fullscreen ? 'Exit full map' : 'Full map',
                      icon: _fullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      onPressed: () =>
                          setState(() => _fullscreen = !_fullscreen),
                    ),
                    SizedBox(
                      width: horizontalControls ? 8 : 0,
                      height: horizontalControls ? 0 : 8,
                    ),
                    _MapControl(
                      label: 'Fit both markers',
                      icon: Icons.center_focus_strong_rounded,
                      accented: true,
                      onPressed: widget.onFit,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: safe.left + 16,
                right: split ? mapRight + 16 : safe.right + 16,
                bottom: attributionBottom,
                child: LayoutBuilder(
                  key: _attributionKey,
                  builder: (context, footer) => Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '© OpenStreetMap contributors',
                              style: InsightTheme.inter(12, c: InsightTheme.ink2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: footer.maxWidth * 0.44),
                        child: _mapInfoRow(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (widget.ready && !_fullscreen)
              Positioned(
                top: split ? safe.top + 16 : null,
                bottom: panelBottom,
                left: split ? null : safe.left + 16,
                right: safe.right + 16,
                width: split ? sideWidth : null,
                child: Align(
                  alignment: split
                      ? Alignment.topRight
                      : Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: panelMaxHeight,
                    ),
                    child: AnimatedSize(
                      duration: _motion,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                       child: _details(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Bare map information link; only its transparent touch target is enlarged.
  Widget _mapInfoRow() => Semantics(
    button: true,
    label: 'Map information',
    excludeSemantics: true,
    onTap: _openMapInfo,
    child: Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InkWell(
          onTap: _openMapInfo,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: InsightTheme.ink2,
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(
                'Map info',
                style: InsightTheme.inter(
                  12,
                  w: FontWeight.w600,
                  c: InsightTheme.ink2,
                ).copyWith(shadows: const [Shadow(color: Colors.white, blurRadius: 4)]),
              )),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _openMapInfo() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MapInfoSheet(showLinks: widget.hasDirectLinks),
  );

  Widget _details() {
    return Container(
      key: _panelKey,
      child: MapDetailPanel(
        title: 'Site details',
        embedded: true,
        headerKey: _detailsHeaderKey,
        initiallyCollapsed: _collapsed,
        collapseLabel: 'site details',
        onCollapsedChanged: (collapsed) => setState(() => _collapsed = collapsed),
        footer: _proceedAction(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                      if (widget.approachNotice || widget.nearSite) ...[
                        _guidanceNotice(),
                        const SizedBox(height: 8),
                      ],
                      LayoutBuilder(
                        builder: (context, box) {
                          final stacked =
                              box.maxWidth <
                              MediaQuery.textScalerOf(context).scale(12) * 20 +
                                  12;
                          final site = _siteMetric();
                          final route = _routeMetric();
                          return stacked
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    site,
                                    const SizedBox(height: 12),
                                    route,
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: site),
                                    const SizedBox(width: 12),
                                    Expanded(child: route),
                                  ],
                                );
                        },
                      ),
                      if (widget.hasRoute && widget.routeFromCache)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Rerouting needs a connection',
                            style: InsightTheme.inter(12, c: InsightTheme.ink3),
                          ),
                        ),
          ],
        ),
      ),
    );
  }

  /// One concise status line for the two states where proximity changes what
  /// the inspector should do next. Extended detail lives in Map info.
  Widget _guidanceNotice() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Icon(
          Icons.info_outline_rounded,
          size: 14,
          color: InsightTheme.ink3,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          widget.nearSite
              ? 'GPS ≤30 m from the mapped point · still confirm in Step 2.'
              : 'Near the mapped site (~100 m) · open GPS Verification when safely stopped/on foot; confirm within 30 m.',
          style: InsightTheme.inter(
            12,
            c: widget.nearSite ? InsightTheme.greenInk : InsightTheme.ink3,
          ),
        ),
      ),
    ],
  );

  // Keep the primary action outside the scrolling guidance, at every distance.
  Widget _proceedAction() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: InsightTheme.primaryGradient,
      borderRadius: BorderRadius.circular(16),
    ),
    child: ElevatedButton(
      key: _actionKey,
      onPressed: widget.onProceed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        shadowColor: Colors.transparent,
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              widget.rework ? 'Save' : 'Proceed to Location',
              textAlign: TextAlign.center,
              style: InsightTheme.inter(
                14,
                w: FontWeight.w600,
                c: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            widget.rework ? Icons.check_rounded : Icons.arrow_forward_rounded,
            size: 18,
          ),
        ],
      ),
    ),
  );

  Widget _siteMetric() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Direct to mapped site', style: InsightTheme.inter(12)),
      const SizedBox(height: 6),
      if (widget.hasDeviceLocation) ...[
        Text(
          widget.distanceMeters == null
              ? 'Unavailable'
              : _distance(widget.distanceMeters!),
          style: InsightTheme.inter(
            22,
            w: FontWeight.w700,
            c: InsightTheme.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.gpsReliable
              ? 'Straight line to mapped point'
              : 'GPS old or imprecise · approximate',
          style: InsightTheme.inter(12, c: InsightTheme.ink3),
        ),
      ] else ...[
        Text(
          'Location unavailable',
          style: InsightTheme.inter(13, w: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: widget.retryingLocation ? null : widget.onRetryLocation,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          icon: widget.retryingLocation
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location_rounded, size: 16),
          label: Text(
            widget.retryingLocation ? 'Retrying location' : 'Retry location',
            style: InsightTheme.inter(12),
          ),
        ),
      ],
    ],
  );

  Widget _routeMetric() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.route_rounded,
              size: 14,
              color: InsightTheme.blueInk,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.hasRoute && widget.routeFromCache
                  ? 'Saved road route'
                  : 'Road route',
              style: InsightTheme.inter(12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      if (widget.hasRoute) ...[
        Text(
          widget.routeDistanceMeters == null &&
                  widget.routeDurationSeconds == null
              ? 'Estimate unavailable'
              : widget.routeEstimateStale
              ? 'Estimate out of date'
              : widget.routeDistanceMeters == null
              ? 'Road length unavailable'
              : _distance(widget.routeDistanceMeters!),
          style: InsightTheme.inter(
            15,
            w: FontWeight.w700,
            c: InsightTheme.ink,
          ),
        ),
        if (!widget.routeEstimateStale && widget.routeDurationSeconds != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'ESTIMATED drive · ~${_duration(widget.routeDurationSeconds!)}',
              style: InsightTheme.inter(12, w: FontWeight.w600),
            ),
          ),
        // Route limitations ("roads only · not traffic-aware; direct links
        // excluded") moved into the Map info sheet with the other extended
        // explanations; the estimate itself stays visible.
      ] else ...[
        Text(
          'Road route unavailable',
          style: InsightTheme.inter(13, w: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'A connection is needed to request a road route. Street tiles may be unavailable offline.',
          style: InsightTheme.inter(12, c: InsightTheme.ink3),
        ),
      ],
    ],
  );

  static String _distance(double meters) => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';

  static String _duration(double seconds) {
    if (seconds < 60) return 'less than a minute';
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.accented = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool accented;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: const EdgeInsets.all(4),
      icon: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 44,
            height: 44,
            decoration: InsightTheme.glassIconButtonDecoration(),
            child: Icon(icon, size: 18,
              color: accented ? InsightTheme.blueInk : InsightTheme.ink),
          ),
        ),
      ),
    ),
  );
}

/// One-tap reference for the map details that used to run inside the
/// details panel: boundary provenance, unverified-link truthfulness, route
/// limitations and the GPS precision gates. Presentation only — the
/// wording mirrors what the panel showed before.
class _MapInfoSheet extends StatelessWidget {
  const _MapInfoSheet({required this.showLinks});

  final bool showLinks;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          decoration: BoxDecoration(
            color: InsightTheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
            border: Border.all(color: InsightTheme.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: InsightTheme.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Map information',
                      style: InsightTheme.urbanist(16, w: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close map information',
                    onPressed: () => Navigator.of(context).pop(),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: InsightTheme.ink2,
                    ),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 4),
                      _infoSection(Icons.polyline_rounded, 'Rosario boundary', [
                        '– –  Rosario boundary · MPDO Rosario',
                        'Dashed line marking the Rosario municipal boundary. Reference only — it does not complete or authorize an inspection step.',
                      ]),
                      _infoSection(
                          Icons.more_horiz_rounded,
                          'Unverified links',
                          [
                            if (showLinks) '··· Unverified links',
                            'Dotted links are schematic straight lines, not verified roads or walkable access. Small gaps or GPS uncertainty may hide a link; zoom in to inspect short links.',
                          ],
                        ),
                      _infoSection(Icons.route_rounded, 'Road route estimate', [
                        'Estimates use mapped roads only — not traffic-aware; direct links excluded.',
                        'Saved geometry is kept offline, but rerouting and street tiles may be missing, and a fresh estimate needs a connection.',
                      ]),
                      _infoSection(Icons.my_location_rounded, 'GPS precision', [
                        'The GPS-to-road link and the ~100 m notice need a fix ≤15 s old with accuracy ≤25 m. Step 2 confirms within 30 m when safely stopped or on foot.',
                        'Step 2 gives direct compass orientation when safely stopped/on foot. A bearing is not a verified access path.',
                      ]),
                      _infoSection(Icons.layers_rounded, 'Map data', [
                        'Map tiles and street data: © OpenStreetMap contributors.',
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoSection(IconData icon, String title, List<String> lines) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: InsightTheme.blueInk),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: InsightTheme.inter(13, w: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        line,
                        style: InsightTheme.inter(12, c: InsightTheme.ink2),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}
