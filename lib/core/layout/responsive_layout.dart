import 'package:flutter/material.dart';

/// Width classes are *layout* classes, not device identities.
///
/// A phone in landscape and a small tablet can share a width class, and a
/// tablet in portrait can share one with a large phone. Only the available box
/// matters, never the device model or the raw orientation flag.
enum InsightWidthClass {
  /// Phones, and any viewport narrower than [InsightBreakpoints.mediumWidth].
  compact,

  /// Small tablets, and phones in landscape.
  medium,

  /// Large tablets, desktops and wide browser windows.
  expanded;

  bool get isCompact => this == InsightWidthClass.compact;
  bool get isMedium => this == InsightWidthClass.medium;
  bool get isExpanded => this == InsightWidthClass.expanded;
}

/// The single place responsive decisions are made from.
///
/// Screens ask this object questions instead of reading
/// `MediaQuery.of(context).orientation`, so breakpoints stay centralised and
/// cannot drift apart between screens.
@immutable
class InsightBreakpoints {
  const InsightBreakpoints(this.size);

  /// Reads the *size* only, so padding changes (offline banner, SafeArea,
  /// keyboard) never trigger a responsive rebuild.
  factory InsightBreakpoints.of(BuildContext context) =>
      InsightBreakpoints(MediaQuery.sizeOf(context));

  // ── Breakpoints ────────────────────────────────────────────────────────
  // Tuned once here; no screen may hardcode its own width.

  /// Below this the layout is a single column.
  static const double mediumWidth = 600;

  /// At or above this there is room for genuinely wide content.
  static const double expandedWidth = 900;

  /// Shorter than this and vertical space is the scarce resource: a phone in
  /// landscape. Horizontal space may still be plentiful.
  static const double shortHeight = 480;

  /// Two side-by-side panes need both enough width and enough height,
  /// otherwise the secondary pane becomes an unusable sliver.
  static const double splitMinWidth = 720;
  static const double splitMinHeight = 340;

  /// Readable line length for forms and text-first content.
  static const double contentMaxWidth = 640;

  /// For content that benefits from being wider (cards, dashboards).
  static const double contentMaxWidthWide = 900;

  /// Minimum comfortable touch target, per the accessibility contract.
  static const double minTouchTarget = 48;

  final Size size;

  double get width => size.width;
  double get height => size.height;

  InsightWidthClass get widthClass {
    if (width >= expandedWidth) return InsightWidthClass.expanded;
    if (width >= mediumWidth) return InsightWidthClass.medium;
    return InsightWidthClass.compact;
  }

  bool get isCompactWidth => widthClass.isCompact;
  bool get isMediumWidth => widthClass.isMedium;
  bool get isExpandedWidth => widthClass.isExpanded;

  /// Vertical space is scarce — typically a phone in landscape.
  bool get isShortHeight => height < shortHeight;
  bool get isTallHeight => !isShortHeight;

  bool get isLandscape => width > height;
  bool get isPortrait => !isLandscape;

  /// Whether a primary/secondary split is worth it right now.
  ///
  /// Requires width *and* height: a wide-but-tall tablet portrait still gets a
  /// split, but a cramped viewport never does, because a half-height pane is
  /// not a usable pane.
  bool get canSplitTwoPane =>
      width >= splitMinWidth && height >= splitMinHeight;

  /// Forms, text and settings never stretch across a whole tablet.
  bool get needsContentConstraint => width > contentMaxWidth;

  @override
  String toString() =>
      'InsightBreakpoints(${width.toStringAsFixed(0)}x'
      '${height.toStringAsFixed(0)}, ${widthClass.name}'
      '${isShortHeight ? ', shortHeight' : ''})';
}

/// Convenience access so call sites read as `context.responsive.isShortHeight`.
extension ResponsiveContext on BuildContext {
  InsightBreakpoints get responsive => InsightBreakpoints.of(this);
}

/// Caps content width and centres it, so a wide viewport does not produce
/// 1200px-wide text lines or stretched cards.
///
/// Set [fill] for maps, camera previews and other spatial canvases that are
/// meant to use the whole available area.
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = InsightBreakpoints.contentMaxWidth,
    this.fill = false,
    this.padding,
  });

  /// Content that should stay readable but may use more than the form width.
  const ConstrainedContent.wide({
    super.key,
    required this.child,
    this.fill = false,
    this.padding,
  }) : maxWidth = InsightBreakpoints.contentMaxWidthWide;

  final Widget child;
  final double maxWidth;

  /// Opt out of the width cap: maps, camera and other spatial visuals.
  final bool fill;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    if (fill) return content;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: content,
      ),
    );
  }
}

/// A primary/secondary layout that adapts instead of merely reflowing.
///
/// Compact (or too-short) viewports stack vertically. Where a split is
/// worthwhile the primary stays dominant at [primaryFlex] and the secondary
/// detail pane takes [secondaryFlex].
///
/// The secondary pane is expected to be independently scrollable, so a long
/// detail list scrolls inside its own pane while the primary visual stays put
/// and fully visible.
class SplitPane extends StatelessWidget {
  const SplitPane({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 62,
    this.secondaryFlex = 38,
    this.stackGap = 16,
    this.splitGap = 16,
  });

  /// Primary keeps the larger share — for map-first screens that is the map.
  final Widget primary;

  /// Secondary detail/status/actions.
  final Widget secondary;

  final int primaryFlex;
  final int secondaryFlex;
  final double stackGap;
  final double splitGap;

  @override
  Widget build(BuildContext context) {
    final bp = context.responsive;
    if (!bp.canSplitTwoPane) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          primary,
          SizedBox(height: stackGap),
          secondary,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: primaryFlex, child: primary),
        SizedBox(width: splitGap),
        Expanded(flex: secondaryFlex, child: secondary),
      ],
    );
  }
}

/// A screen body with a constant-height header above an adaptive body.
///
/// Used where a screen has a fixed header — the inspection step progress bar,
/// the GPS header — and the space beneath it must rearrange rather than simply
/// shorten. Stacked on phones; two panes where there is room, with the
/// secondary pane scrolling independently so it can never push the primary
/// visual off-screen.
///
/// The secondary pane is wrapped in a scroll view *only* in the split
/// composition. Stacked, it keeps its intrinsic height, which is what the
/// accepted portrait layouts already rely on.
class HeaderSplitBody extends StatelessWidget {
  const HeaderSplitBody({
    super.key,
    required this.primary,
    this.header,
    this.secondary,
    this.primaryFlex = 62,
    this.secondaryFlex = 38,
    this.splitGap = 16,
    this.stackGap = 0,
  });

  /// Constant header above the body. Omit for a fullscreen/immersive mode.
  final Widget? header;

  /// The primary content: a visual, map, dial or the main form section.
  final Widget primary;

  /// Secondary detail, metrics and actions. Omitted while there is nothing to
  /// show (loading, errored).
  final Widget? secondary;

  final int primaryFlex;
  final int secondaryFlex;
  final double splitGap;
  final double stackGap;

  @override
  Widget build(BuildContext context) {
    final hasSecondary = secondary != null;
    final split = hasSecondary && context.responsive.canSplitTwoPane;

    final Widget body = split
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: primaryFlex, child: primary),
              SizedBox(width: splitGap),
              Expanded(
                flex: secondaryFlex,
                // Independent scroll: long detail must not squeeze the primary.
                child: SingleChildScrollView(child: secondary!),
              ),
            ],
          )
        : Column(
            children: [
              Expanded(child: primary),
              if (hasSecondary) ...[
                if (stackGap > 0) SizedBox(height: stackGap),
                // Flexible + internal scroll, so a fixed-height detail block
                // can never push the column past the viewport. Loose fit keeps
                // the intrinsic height whenever there IS room for it, which is
                // what preserves the accepted portrait appearance exactly.
                Flexible(
                  child: SingleChildScrollView(child: secondary),
                ),
              ],
            ],
          );

    if (header == null) return body;
    return Column(
      children: [
        header!,
        Expanded(child: body),
      ],
    );
  }
}

/// LayoutBuilder wrapper for the rare case that genuinely needs raw
/// constraints (infinite width, an unbounded parent, or a draggable viewport).
///
/// Prefer [context.responsive] for breakpoint decisions.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, InsightBreakpoints bp) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => builder(
          context,
          InsightBreakpoints(constraints.biggest),
        ),
      );
}