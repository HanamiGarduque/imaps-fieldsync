import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/insight_theme.dart';
import '../../core/widgets/field_form_widgets.dart';
import '../../core/widgets/fieldsync_brand.dart';
import 'guide_coordinator.dart';
import 'guide_layout.dart';
import 'guide_preferences.dart';
import 'guide_script.dart';
import 'guide_targets.dart';

class GuideOverlay extends StatefulWidget {
  const GuideOverlay({
    super.key,
    required this.coordinator,
    required this.targets,
    required this.child,
    required this.onOpenTask,
    this.onViewportInsetsChanged,
  });
  final GuideCoordinator coordinator;
  final GuideTargetRegistry targets;
  final Widget child;
  final VoidCallback onOpenTask;
  final ValueChanged<EdgeInsets>? onViewportInsetsChanged;

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay>
    with SingleTickerProviderStateMixin {
  final _hostKey = GlobalKey();
  final _headerKey = GlobalKey(),
      _footerKey = GlobalKey(),
      _languageKey = GlobalKey(),
      _copyKey = GlobalKey();
  final _focus = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final Map<ScrollableState, double> _scrollOrigins = {};
  late final AnimationController _pulse;
  FocusNode? _previousFocus;
  Rect? _target, _anchor, _navigation;
  Size _size = Size.zero;
  int _measuredGeneration = -1, _scrolledGeneration = -1, _lastStage = -1;
  bool _tracking = false, _scrolling = false, _wasVisible = false;
  bool _reducedMotion = true, _details = false, _starting = false;
  double _pulseStrength = 1;
  double? _coachMinimum, _coachHeight;
  double? _coachWidth;
  EdgeInsets _viewportInsets = EdgeInsets.zero;
  EdgeInsets? _reportedInsets;
  int _layoutRevision = 0;
  int? _pointerGeneration, _pointerRevision;
  Size? _pointerSize;
  Rect? _pointerTarget;
  GuideLanguage? _invitationLanguage;

  GuideCoordinator get guide => widget.coordinator;
  bool get _visible =>
      guide.phase == GuidePhase.invitation || guide.phase == GuidePhase.active;
  GuideStop get _stop => guideStops[guide.stopIndex];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    guide.addListener(_onGuideChanged);
    widget.targets.addListener(_track);
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (_reducedMotion) _pulse.stop();
    _coachMinimum = null;
    _resetViewport();
    _syncVisibility();
    _track();
  }

  @override
  void didUpdateWidget(GuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coordinator != guide) {
      oldWidget.coordinator.removeListener(_onGuideChanged);
      guide.addListener(_onGuideChanged);
    }
    if (oldWidget.targets != widget.targets) {
      oldWidget.targets.removeListener(_track);
      widget.targets.addListener(_track);
      _target = _anchor = null;
      _measuredGeneration = -1;
    }
    _track();
  }

  void _syncVisibility() {
    if (_visible && !_wasVisible) {
      _previousFocus = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible) _focus.requestFocus();
      });
    } else if (!_visible && _wasVisible) {
      _pulse.stop();
      _restoreScroll();
      final previous = _previousFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_visible && previous?.context?.mounted == true) {
          previous!.requestFocus();
        }
      });
      _lastStage = -1;
    }
    if (_visible) {
      final stage = guide.phase == GuidePhase.invitation ? 0 : _stop.stage;
      if (stage != _lastStage) {
        _pulseStrength = _lastStage < 0 ? 1 : .55;
        _pulse.duration = Duration(milliseconds: _lastStage < 0 ? 900 : 450);
        if (!_reducedMotion) _pulse.forward(from: 0);
        _lastStage = stage;
      }
    }
    _wasVisible = _visible;
  }

  void _onGuideChanged() {
    if (!mounted) return;
    _target = null;
    _measuredGeneration = -1;
    _scrolling = false;
    _details = false;
    _coachMinimum = null;
    _resetViewport(keepInsets: guide.phase == GuidePhase.active);
    _syncVisibility();
    setState(() {});
    _track();
  }

  void _onFontsChanged() {
    if (!mounted) return;
    setState(() => _coachMinimum = null);
    _track();
  }

  void _resetViewport({bool keepInsets = false}) {
    if (!keepInsets) _viewportInsets = EdgeInsets.zero;
    _coachWidth = null;
    _scrolledGeneration = -1;
    _layoutRevision++;
  }

  void _reportViewport(EdgeInsets insets) {
    if (_reportedInsets == insets) return;
    _reportedInsets = insets;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedInsets != insets) return;
      widget.onViewportInsetsChanged?.call(insets);
      _scrolledGeneration = -1;
      _target = null;
      _measuredGeneration = -1;
      _track();
    });
  }

  Rect _targetViewport(MediaQueryData media) {
    final safe = _paintBounds(media);
    return Rect.fromLTRB(
      safe.left,
      math.max(
        safe.top,
        math.max(media.viewPadding.top, media.padding.top) +
            _viewportInsets.top +
            12,
      ),
      safe.right - _viewportInsets.right,
      math.min(
        math.min(safe.bottom, (_navigation?.top ?? safe.bottom + 6) - 6),
        _size.height -
            math.max(media.viewPadding.bottom, media.padding.bottom) -
            _viewportInsets.bottom -
            12,
      ),
    );
  }

  Rect? _halo(Rect? target, Rect safe) => target?.inflate(6).intersect(safe);

  // Gesture edges reserve input for Android Back, not invisible screen space.
  // Paint the whole visible feature while keeping controls/taps gesture-safe.
  Rect _paintBounds(MediaQueryData media) => Rect.fromLTRB(
    math.max(media.viewPadding.left, media.padding.left),
    math.max(media.viewPadding.top, media.padding.top),
    _size.width - math.max(media.viewPadding.right, media.padding.right),
    _size.height -
        math.max(
          math.max(media.viewPadding.bottom, media.padding.bottom),
          media.viewInsets.bottom,
        ),
  );

  Rect _safeRect(MediaQueryData media) => Rect.fromLTRB(
    math.max(media.viewPadding.left, media.systemGestureInsets.left) + 12,
    math.max(media.viewPadding.top, media.padding.top) + 12,
    _size.width -
        math.max(media.viewPadding.right, media.systemGestureInsets.right) -
        12,
    _size.height -
        math.max(
          math.max(media.viewPadding.bottom, media.padding.bottom),
          media.viewInsets.bottom,
        ) -
        12,
  );

  // Observe only frames Flutter already renders. No timer, retry loop, tree scan,
  // or frame request is used to wait for a missing target.
  void _track() {
    if (!mounted || !_visible || _tracking) return;
    _tracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tracking = false;
      if (!mounted || !_visible) return;
      _measure();
      _track();
    });
  }

  void _measure() {
    final host = _hostKey.currentContext?.findRenderObject();
    if (host is! RenderBox || !host.attached || !host.hasSize) return;
    final token = guide.generation;
    final id = guide.phase == GuidePhase.invitation
        ? 'guide_fingerprint'
        : _stop.targetId;
    final anchor = widget.targets.rectFor('guide_fingerprint', host);
    final navigation = widget.targets.rectFor('guide_navigation', host);
    final oldNavigation = _navigation;
    _navigation = navigation;
    double height(GlobalKey key) {
      final box = key.currentContext?.findRenderObject();
      return box is RenderBox && box.hasSize ? box.size.height : 0;
    }

    final invitation = guide.phase == GuidePhase.invitation;
    final controls =
        (invitation ? 32 : 24) +
        height(_headerKey) +
        height(_languageKey) +
        height(_footerKey) +
        8;
    final copyHeight = height(_copyKey);
    final minimum =
        controls +
        math.min(
          copyHeight,
          invitation ? 200 : MediaQuery.textScalerOf(context).scale(14) * 1.4,
        );
    final desired = controls + copyHeight + 2;
    var target = widget.targets.rectFor(id, host);
    if (target != null && _scrolledGeneration != token) {
      final targetContext = widget.targets.contextFor(id);
      final scrollable = targetContext == null
          ? null
          : Scrollable.maybeOf(targetContext, axis: Axis.vertical);
      _scrolledGeneration = token;
      if (scrollable != null) {
        _scrolling = true;
        unawaited(
          _revealTarget(targetContext!, token).then((_) {
            if (!mounted || !_visible || token != guide.generation) return;
            setState(() => _scrolling = false);
          }),
        );
        target = null;
      }
    }
    // A tall section remains the target. Show its actual visible viewport,
    // rather than shrinking the highlight to its heading or warning the user
    // about the guide's layout. Native scrolling brings its start into view.
    final measured = _scrolling || target == null
        ? null
        : _visibleTarget(id, host);
    if (_target != measured ||
        _anchor != anchor ||
        oldNavigation != navigation ||
        _measuredGeneration != token ||
        _coachMinimum != minimum ||
        _coachHeight != desired) {
      setState(() {
        _target = measured;
        _anchor = anchor;
        _measuredGeneration = token;
        _coachMinimum = minimum;
        _coachHeight = desired;
      });
    }
  }

  Rect? _visibleTarget(String id, RenderBox host) {
    final target = widget.targets.rectFor(id, host);
    var visibleRegion = id == 'guide_fingerprint'
        ? _paintBounds(MediaQuery.of(context))
        : _targetViewport(MediaQuery.of(context));
    final targetContext = widget.targets.contextFor(id);
    var parent = targetContext == null
        ? null
        : Scrollable.maybeOf(targetContext);
    while (parent != null) {
      final box = parent.context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        visibleRegion = visibleRegion.intersect(
          MatrixUtils.transformRect(
            box.getTransformTo(host),
            Offset.zero & box.size,
          ),
        );
      }
      parent = Scrollable.maybeOf(parent.context);
    }
    final clipped = target?.intersect(visibleRegion);
    return clipped == null || clipped.isEmpty ? null : clipped;
  }

  Future<void> _revealTarget(BuildContext targetContext, int token) {
    final object = targetContext.findRenderObject();
    if (object == null) return Future<void>.value();
    // Native ancestor lookup, vertical lanes only: aligning a label inside a
    // PageView would otherwise drag its assignment card sideways offscreen.
    final futures = <Future<void>>[];
    var current = targetContext;
    var scrollable = Scrollable.maybeOf(current);
    while (scrollable != null &&
        mounted &&
        _visible &&
        token == guide.generation) {
      if (scrollable.position.axis == Axis.vertical) {
        _scrollOrigins.putIfAbsent(
          scrollable,
          () => scrollable!.position.pixels,
        );
        futures.add(
          scrollable.position.ensureVisible(
            current.findRenderObject()!,
            targetRenderObject: object,
            alignment: .1,
            duration: _reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      current = scrollable.context;
      scrollable = Scrollable.maybeOf(current);
    }
    return Future.wait(futures);
  }

  void _restoreScroll() {
    for (final entry in _scrollOrigins.entries) {
      if (!entry.key.mounted || !entry.key.position.hasPixels) continue;
      final position = entry.key.position;
      position.jumpTo(
        entry.value.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
    _scrollOrigins.clear();
  }

  void _advance() {
    if (guide.phase != GuidePhase.active) return;
    if (_stop.id == 'G15') {
      widget.onOpenTask();
    } else if (guide.stopIndex == guideStops.length - 1) {
      unawaited(guide.finish());
    } else {
      guide.next();
    }
  }

  void _backgroundTap(TapUpDetails event) {
    if (!_safeRect(MediaQuery.of(context)).contains(event.localPosition)) {
      return;
    }
    if (guide.phase != GuidePhase.active) return;
    if (event.localPosition.dx < _size.width / 2) {
      guide.back();
    } else {
      _advance();
    }
  }

  bool _sampleStillCurrent(int generation, Size size, Rect rect) {
    final host = _hostKey.currentContext?.findRenderObject();
    return mounted &&
        _visible &&
        !_scrolling &&
        guide.generation == generation &&
        _measuredGeneration == generation &&
        host is RenderBox &&
        host.size == size &&
        _pointerGeneration == generation &&
        _pointerSize == size &&
        _pointerRevision == _layoutRevision &&
        _pointerTarget == rect &&
        _visibleTarget('guide_task_card', host) == rect;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return PopScope(
      canPop: guide.phase == GuidePhase.idle,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(guide.skip());
      },
      child: GuideTargetScope(
        registry: widget.targets,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (size != _size) {
              _size = size;
              _target = _anchor = null;
              _measuredGeneration = -1;
              _scrolledGeneration = -1;
              _coachMinimum = null;
              _resetViewport();
            }
            final invitation = guide.phase == GuidePhase.invitation;
            final language = invitation
                ? (_invitationLanguage ?? guide.language)
                : guide.language;
            final labels = GuideLabels(language);
            final copy = invitation
                ? (labels.isTagalog
                      ? guideInvitationTagalog
                      : guideInvitationEnglish)
                : _stop.copyFor(language);
            final safe = _safeRect(MediaQuery.of(context));
            // G01 includes language and Start/Not Now, unlike the compact
            // active speech bubble. Keep its independent readable width and
            // measured control minimum even before the first measurement.
            final placement = invitation
                ? GuidePlacement(
                    bubble: Rect.fromLTWH(
                      safe.left,
                      safe.top,
                      math.min(420, safe.width),
                      math.min(
                        safe.height,
                        _coachMinimum == null
                            ? 420
                            : math.max(_coachMinimum!, _coachHeight ?? 0),
                      ),
                    ),
                    spotlight: _target,
                    overview: _target == null,
                  )
                : GuidePlacement.resolve(
                    safe: safe,
                    target: _target,
                    anchor: _anchor,
                    desiredCoach: Size(
                      math.min(_coachWidth ?? 360, safe.width),
                      _coachHeight ?? 240,
                    ),
                    minimumCoach: Size(
                      math.min(invitation ? 360 : 188, safe.width),
                      _coachMinimum ?? 160,
                    ),
                    viewportInsets: _viewportInsets,
                  );
            if (visible &&
                !invitation &&
                placement.viewportInsets != EdgeInsets.zero) {
              _viewportInsets = placement.viewportInsets;
            }
            if (visible && !invitation && _coachMinimum != null) {
              _coachWidth = math.min(
                _coachWidth ?? 360,
                placement.bubble.width,
              );
            }
            _reportViewport(
              visible && !invitation ? _viewportInsets : EdgeInsets.zero,
            );
            final spotlight = _halo(
              placement.spotlight,
              _paintBounds(MediaQuery.of(context)),
            );
            final taskProxy = placement.spotlight?.intersect(safe);
            final generation = guide.generation;
            return Stack(
              key: _hostKey,
              fit: StackFit.expand,
              children: [
                ExcludeFocus(
                  excluding: visible,
                  child: ExcludeSemantics(
                    excluding: visible,
                    child: IgnorePointer(
                      ignoring: visible,
                      child: widget.child,
                    ),
                  ),
                ),
                if (visible) ...[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey('guide-scrim'),
                        painter: GuideScrimPainter(
                          target: spotlight,
                          anchor: _anchor,
                          pulse: _reducedMotion ? null : _pulse,
                          strength: _pulseStrength,
                        ),
                      ),
                    ),
                  ),
                  if (spotlight != null && placement.arrowTip != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('guide-arrow'),
                          painter: GuideArrowPainter(
                            bubble: placement.bubble,
                            tip: placement.arrowTip!,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _backgroundTap,
                      ),
                    ),
                  ),
                  if (!invitation &&
                      _stop.id == 'G15' &&
                      taskProxy != null &&
                      !taskProxy.isEmpty)
                    Positioned.fromRect(
                      rect: taskProxy,
                      child: Semantics(
                        button: true,
                        label: labels.isTagalog
                            ? 'Tingnan ang inspection sa gabay'
                            : 'Explore inspection in the guide',
                        child: GestureDetector(
                          key: const ValueKey('guide-task-proxy'),
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) {
                            _pointerGeneration = generation;
                            _pointerSize = size;
                            _pointerRevision = _layoutRevision;
                            _pointerTarget = placement.spotlight;
                          },
                          onTap: () {
                            if (_sampleStillCurrent(
                              generation,
                              size,
                              placement.spotlight!,
                            )) {
                              _advance();
                            }
                          },
                        ),
                      ),
                    ),
                  if (_anchor != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('guide-speech-tail'),
                          painter: GuideSpeechTailPainter(
                            bubble: placement.bubble,
                            anchor: _anchor!,
                          ),
                        ),
                      ),
                    ),
                  Positioned.fromRect(
                    rect: placement.bubble,
                    child: FocusScope(
                      node: _focus,
                      autofocus: true,
                      child: FocusTraversalGroup(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: _coach(context, copy, labels, invitation),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _coach(
    BuildContext context,
    GuideCopy copy,
    GuideLabels labels,
    bool invitation,
  ) {
    if (!invitation) return _compactCoach(copy, labels);
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      foregroundColor: InsightTheme.blueInk,
      textStyle: InsightTheme.inter(14, w: FontWeight.w600),
    );
    return Material(
      key: const ValueKey('guide-coach'),
      color: InsightTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: InsightTheme.blue1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!invitation)
              Align(
                key: _headerKey,
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('guide-skip'),
                  onPressed: () => unawaited(guide.skip()),
                  style: buttonStyle,
                  child: Text(labels.skip),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey(
                  'guide-copy-${invitation ? 'invitation' : _stop.id}-${labels.language.name}',
                ),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Column(
                    key: _copyKey,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (invitation)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: FieldSyncBrand(
                            variant: FieldSyncBrandVariant.symbol,
                            height: 24,
                          ),
                        ),
                      if (!invitation) ...[
                        Text(
                          _stop.progress(labels.language),
                          style: InsightTheme.inter(
                            12,
                            w: FontWeight.w700,
                            c: InsightTheme.blueInk,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _stop.stageTitle(labels.language),
                          style: InsightTheme.inter(12, c: InsightTheme.ink2),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        copy.title,
                        style: InsightTheme.urbanist(
                          18,
                          w: FontWeight.w700,
                          c: InsightTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        copy.message,
                        style: InsightTheme.inter(
                          14,
                          c: InsightTheme.ink2,
                          h: 1.4,
                        ),
                      ),
                      if (!invitation && guide.stopIndex == 0) ...[
                        const SizedBox(height: 12),
                        Text(
                          labels.navigation,
                          style: InsightTheme.inter(12, c: InsightTheme.ink2),
                        ),
                      ],
                      if (copy.details != null) ...[
                        TextButton(
                          onPressed: () => setState(() => _details = !_details),
                          style: buttonStyle,
                          child: Text(
                            _details ? labels.close : labels.moreDetails,
                          ),
                        ),
                        if (_details)
                          Text(
                            copy.details!,
                            style: InsightTheme.inter(
                              14,
                              c: InsightTheme.ink2,
                              h: 1.4,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (invitation)
              Column(
                key: _languageKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    labels.chooseLanguage,
                    style: InsightTheme.inter(12, c: InsightTheme.blueInk),
                  ),
                  const SizedBox(height: 8),
                  FieldSegmentedControl<GuideLanguage>(
                    labels: const {
                      GuideLanguage.tagalog: 'Filipino (Tagalog)',
                      GuideLanguage.english: 'English',
                    },
                    value: labels.language,
                    onChanged: (language) => setState(() {
                      _invitationLanguage = language;
                      _coachMinimum = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            LayoutBuilder(
              key: _footerKey,
              builder: (context, constraints) {
                final half = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(minWidth: half),
                      child: TextButton(
                        key: ValueKey(
                          invitation ? 'guide-not-now' : 'guide-back',
                        ),
                        onPressed: invitation
                            ? () => unawaited(guide.skip())
                            : guide.stopIndex == 0
                            ? null
                            : guide.back,
                        style: buttonStyle,
                        child: Text(
                          invitation ? labels.notNow : labels.back,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(minWidth: half),
                      child: FilledButton(
                        key: ValueKey(
                          invitation ? 'guide-start' : 'guide-next',
                        ),
                        onPressed: _starting
                            ? null
                            : invitation
                            ? () async {
                                setState(() => _starting = true);
                                await guide.start(labels.language);
                                if (mounted) setState(() => _starting = false);
                              }
                            : _advance,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          backgroundColor: InsightTheme.blue1,
                          foregroundColor: Colors.white,
                          textStyle: InsightTheme.inter(14, w: FontWeight.w600),
                        ),
                        child: Text(
                          invitation
                              ? labels.start
                              : guide.stopIndex == guideStops.length - 1
                              ? labels.done
                              : labels.next,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactCoach(GuideCopy copy, GuideLabels labels) {
    final last = guide.stopIndex == guideStops.length - 1;
    final stageStops = guideStops
        .where((stop) => stop.stage == _stop.stage)
        .toList();
    final detailsLabel = _details ? labels.close : labels.moreDetails;
    return Material(
      key: const ValueKey('guide-coach'),
      color: InsightTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: InsightTheme.blue1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              key: _headerKey,
              children: [
                const FieldSyncBrand(
                  variant: FieldSyncBrandVariant.symbol,
                  height: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    label:
                        '${_stop.stageTitle(labels.language)}. ${_stop.progress(labels.language)}',
                    excludeSemantics: true,
                    child: Text(
                      '${_stop.stage}/$guideStageCount · ${stageStops.indexOf(_stop) + 1}/${stageStops.length}',
                      style: InsightTheme.inter(
                        12,
                        w: FontWeight.w700,
                        c: InsightTheme.blueInk,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('guide-skip'),
                  tooltip: labels.skip,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () => unawaited(guide.skip()),
                  icon: Icon(Icons.close_rounded, semanticLabel: labels.skip),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey('guide-copy-${_stop.id}-${labels.language.name}'),
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Column(
                    key: _copyKey,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        copy.title,
                        style: InsightTheme.urbanist(
                          18,
                          w: FontWeight.w700,
                          c: InsightTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _details ? copy.message : copy.summary ?? copy.message,
                        style: InsightTheme.inter(
                          14,
                          c: InsightTheme.ink2,
                          h: 1.4,
                        ),
                      ),
                      if (_details) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_stop.stageTitle(labels.language)} · ${_stop.progress(labels.language)}',
                          style: InsightTheme.inter(
                            12,
                            c: InsightTheme.blueInk,
                          ),
                        ),
                        if (copy.details != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            copy.details!,
                            style: InsightTheme.inter(
                              14,
                              c: InsightTheme.ink2,
                              h: 1.4,
                            ),
                          ),
                        ],
                        if (guide.stopIndex == 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            labels.navigation,
                            style: InsightTheme.inter(12, c: InsightTheme.ink2),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              key: _footerKey,
              builder: (context, constraints) {
                final narrow =
                    constraints.maxWidth < 236 ||
                    MediaQuery.textScalerOf(context).scale(14) > 21;
                return Row(
                  children: [
                    if (narrow)
                      IconButton(
                        key: const ValueKey('guide-details'),
                        tooltip: detailsLabel,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: _toggleDetails,
                        icon: Icon(
                          _details
                              ? Icons.unfold_less_rounded
                              : Icons.info_outline_rounded,
                          semanticLabel: detailsLabel,
                        ),
                      )
                    else
                      Expanded(
                        child: TextButton(
                          key: const ValueKey('guide-details'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            foregroundColor: InsightTheme.blueInk,
                            textStyle: InsightTheme.inter(
                              14,
                              w: FontWeight.w600,
                            ),
                          ),
                          onPressed: _toggleDetails,
                          child: Text(detailsLabel),
                        ),
                      ),
                    IconButton(
                      key: const ValueKey('guide-back'),
                      tooltip: labels.back,
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: guide.stopIndex == 0 ? null : guide.back,
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        semanticLabel: labels.back,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (last)
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('guide-next'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.all(8),
                            backgroundColor: InsightTheme.blue1,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _advance,
                          child: Text(labels.done, textAlign: TextAlign.center),
                        ),
                      )
                    else
                      IconButton.filled(
                        key: const ValueKey('guide-next'),
                        tooltip: labels.next,
                        style: IconButton.styleFrom(
                          backgroundColor: InsightTheme.blue1,
                          foregroundColor: Colors.white,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: _advance,
                        icon: Icon(
                          Icons.arrow_forward_rounded,
                          semanticLabel: labels.next,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleDetails() => setState(() {
    _details = !_details;
    _coachMinimum = null;
    _target = null;
    _resetViewport();
    _track();
  });

  @override
  void dispose() {
    guide.removeListener(_onGuideChanged);
    widget.targets.removeListener(_track);
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _restoreScroll();
    _focus.dispose();
    _pulse.dispose();
    super.dispose();
  }
}

class GuideSpeechTailPainter extends CustomPainter {
  const GuideSpeechTailPainter({required this.bubble, required this.anchor});
  final Rect bubble, anchor;

  @override
  void paint(Canvas canvas, Size size) {
    final y = anchor.center.dy.clamp(bubble.top + 16, bubble.bottom - 16);
    final tail = Path()
      ..moveTo(bubble.right - 1, y - 8)
      ..lineTo(anchor.left, anchor.center.dy)
      ..lineTo(bubble.right - 1, y + 8)
      ..close();
    canvas.drawPath(tail, Paint()..color = InsightTheme.surface);
    canvas.drawPath(
      tail,
      Paint()
        ..color = InsightTheme.blue1
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(GuideSpeechTailPainter old) =>
      old.bubble != bubble || old.anchor != anchor;
}

class GuideArrowPainter extends CustomPainter {
  const GuideArrowPainter({required this.bubble, required this.tip});
  final Rect bubble;
  final Offset tip;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(
      tip.dx.clamp(bubble.left + 12, bubble.right - 12),
      tip.dy.clamp(bubble.top + 12, bubble.bottom - 12),
    );
    final direction = tip - start;
    final distance = direction.distance;
    if (distance == 0) return;
    final unit = direction / distance;
    final base = tip - unit * 7;
    final perpendicular = Offset(-unit.dy, unit.dx) * 4;
    canvas.drawLine(
      start,
      base,
      Paint()
        ..color = InsightTheme.blue1
        ..strokeWidth = 2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo((base + perpendicular).dx, (base + perpendicular).dy)
        ..lineTo((base - perpendicular).dx, (base - perpendicular).dy)
        ..close(),
      Paint()..color = InsightTheme.blue1,
    );
  }

  @override
  bool shouldRepaint(GuideArrowPainter oldDelegate) =>
      oldDelegate.bubble != bubble || oldDelegate.tip != tip;
}

class GuideScrimPainter extends CustomPainter {
  GuideScrimPainter({
    required this.target,
    required this.anchor,
    this.pulse,
    this.strength = 1,
  }) : super(repaint: pulse);
  final Rect? target, anchor;
  final Animation<double>? pulse;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (target != null) {
      path.addRRect(
        RRect.fromRectAndRadius(target!, const Radius.circular(12)),
      );
    }
    if (anchor != null && (target == null || !target!.overlaps(anchor!))) {
      path.addRRect(
        RRect.fromRectAndRadius(anchor!, const Radius.circular(20)),
      );
    }
    canvas.drawPath(
      path,
      Paint()..color = InsightTheme.ink.withValues(alpha: .42),
    );
    if (target != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(target!, const Radius.circular(12)),
        Paint()
          ..color = InsightTheme.blue1
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (anchor == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(anchor!, const Radius.circular(20)),
      Paint()
        ..color = InsightTheme.blue1.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final value = pulse?.value;
    if (value == null || value >= 1) return;
    for (final delay in [0.0, .2]) {
      final t = ((value - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t == 0 && delay != 0) continue;
      canvas.drawCircle(
        anchor!.center,
        anchor!.shortestSide / 2 + t * 18 * strength,
        Paint()
          ..color = InsightTheme.blue1.withValues(
            alpha: (1 - t) * .3 * strength,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(GuideScrimPainter oldDelegate) =>
      target != oldDelegate.target ||
      anchor != oldDelegate.anchor ||
      pulse != oldDelegate.pulse ||
      strength != oldDelegate.strength;
}
