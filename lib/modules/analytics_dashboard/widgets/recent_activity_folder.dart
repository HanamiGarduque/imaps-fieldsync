import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/insight_theme.dart';

/// One connected folder surface; data and history navigation stay with Home.
class RecentActivityFolder extends StatefulWidget {
  final List<({String key, String label})> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final Widget child;

  const RecentActivityFolder({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.child,
  });

  @override
  State<RecentActivityFolder> createState() => _RecentActivityFolderState();
}

class _RecentActivityFolderState extends State<RecentActivityFolder> {
  final _tabs = ScrollController();
  List<Rect> _tabRects = [];
  double _viewport = 0;
  double _contentWidth = 0;

  @override
  void didUpdateWidget(RecentActivityFolder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCategory != widget.selectedCategory) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabs.hasClients) return;
      final index = widget.categories.indexWhere((tab) => tab.key == widget.selectedCategory);
      if (index < 0 || index >= _tabRects.length) return;
      final rect = _tabRects[index];
      final offset = _tabs.offset;
      final target = (rect.left < offset ? rect.left
          : rect.right > offset + _viewport ? rect.right - _viewport : offset)
          .clamp(0.0, _tabs.position.maxScrollExtent).toDouble();
      if ((target - offset).abs() < 0.5) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _tabs.jumpTo(target);
      } else {
        _tabs.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final tabStyle = DefaultTextStyle.of(context).style.merge(
      InsightTheme.inter(13, w: FontWeight.w600, h: 1.2),
    );
    final headerHeight = math.max(52.0, ((scaler.scale(13) * 1.2 + 28) / 4).ceil() * 4.0);
    return LayoutBuilder(builder: (context, constraints) {
      const overlap = 8.0;
      final widths = [for (final tab in widget.categories) (() {
        final painter = TextPainter(
          text: TextSpan(text: tab.label, style: tabStyle),
          textDirection: Directionality.of(context), textScaler: scaler,
        )..layout();
        final width = math.max(72.0, painter.width + 52);
        painter.dispose();
        return width;
      })()];
      final naturalWidth = widths.fold<double>(0, (sum, width) => sum + width) - overlap * (widths.length - 1);
      final extra = math.max(0.0, constraints.maxWidth - naturalWidth) / widths.length;
      final contentWidth = math.max(constraints.maxWidth, naturalWidth);
      var left = 0.0;
      _tabRects = [for (final width in widths) (() {
        final rect = Rect.fromLTWH(left, 0, width + extra, headerHeight);
        left += rect.width - overlap;
        return rect;
      })()];
      if (_viewport != constraints.maxWidth || _contentWidth != contentWidth) {
        _viewport = constraints.maxWidth;
        _contentWidth = contentWidth;
        _revealSelected();
      }
      final selected = math.max(0, widget.categories.indexWhere((tab) => tab.key == widget.selectedCategory));
      return CustomPaint(
        painter: _ActivityFolderPainter(_tabRects, selected, headerHeight, _tabs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                key: const ValueKey('activity_category_shortcuts'),
                controller: _tabs,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth,
                  height: headerHeight,
                  child: Stack(children: [
                    // The selected tab is the front sheet, including its hit area.
                    for (final i in [for (var i = 0; i < widths.length; i++) if (i != selected) i, selected])
                      Positioned(
                        key: ValueKey('folder_tab_position_${widget.categories[i].key}'),
                        left: _tabRects[i].left, width: _tabRects[i].width,
                        top: i == selected ? 0 : 4, bottom: 0,
                        child: ClipPath(
                          clipper: const _ActivityTabClipper(),
                          child: Semantics(
                            key: ValueKey('activity_folder_tab_${widget.categories[i].key}'),
                            button: true, selected: i == selected,
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                onTap: () => widget.onCategorySelected(widget.categories[i].key),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
                                  child: Center(child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ExcludeSemantics(child: Icon(_categoryIcon(widget.categories[i].key),
                                            size: 16, color: i == selected ? InsightTheme.blue1 : InsightTheme.ink3)),
                                          const SizedBox(width: 4),
                                          Text(widget.categories[i].label, softWrap: false,
                                            style: tabStyle.copyWith(color: i == selected ? InsightTheme.blue1 : InsightTheme.ink3)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      AnimatedOpacity(
                                        opacity: i == selected ? 1 : 0,
                                        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
                                        child: Container(width: 24, height: 3,
                                          decoration: BoxDecoration(color: InsightTheme.blue1, borderRadius: BorderRadius.circular(2))),
                                      ),
                                    ],
                                  )),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            Padding(
              key: const ValueKey('activity_folder_body'),
              padding: const EdgeInsets.all(8),
              child: widget.child,
            ),
          ],
        ),
      );
    });
  }
}

IconData _categoryIcon(String category) => switch (category) {
  'tasks' => Icons.description_rounded,
  'sync' => Icons.sync_rounded,
  'reports' => Icons.bar_chart_rounded,
  _ => Icons.person_outline_rounded,
};

Path _tabPath(Rect rect, {double bodyOverlap = 0}) {
  return Path()
    ..moveTo(rect.left, rect.bottom + bodyOverlap)
    ..lineTo(rect.left, rect.top + 12)
    ..quadraticBezierTo(rect.left, rect.top, rect.left + 12, rect.top)
    ..lineTo(rect.right - 24, rect.top)
    ..quadraticBezierTo(rect.right - 14, rect.top, rect.right - 10, rect.top + 12)
    ..lineTo(rect.right - 4, rect.bottom - 10)
    ..quadraticBezierTo(rect.right, rect.bottom, rect.right, rect.bottom)
    ..lineTo(rect.right, rect.bottom + bodyOverlap)
    ..close();
}

class _ActivityTabClipper extends CustomClipper<Path> {
  const _ActivityTabClipper();
  @override
  Path getClip(Size size) => _tabPath(Offset.zero & size);
  @override
  bool shouldReclip(_ActivityTabClipper oldClipper) => false;
}

/// Paints the active tab and body as a union, so there is no seam to drift
/// apart while the header scrolls. Inactive sheets sit behind that one path.
class _ActivityFolderPainter extends CustomPainter {
  final List<Rect> tabs;
  final int selected;
  final double headerHeight;
  final ScrollController controller;

  _ActivityFolderPainter(this.tabs, this.selected, this.headerHeight, this.controller)
      : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final offset = Offset(-(controller.hasClients ? controller.offset : 0.0), 0);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, headerHeight));
    for (var i = 0; i < tabs.length; i++) {
      if (i == selected) continue;
      final tab = _tabPath(Rect.fromLTRB(tabs[i].left + offset.dx, 4, tabs[i].right + offset.dx, headerHeight));
      canvas.drawPath(tab, Paint()..color = InsightTheme.surface2);
      canvas.drawPath(tab, Paint()..color = InsightTheme.ink3.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke..strokeWidth = 0.75);
    }
    canvas.restore();
    final body = Path()..addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, headerHeight, size.width, size.height - headerHeight), const Radius.circular(20)));
    final joined = Path.combine(PathOperation.union, body, _tabPath(tabs[selected].shift(offset), bodyOverlap: 20));
    final outline = Path.combine(PathOperation.intersect, joined, Path()..addRect(Offset.zero & size));
    canvas.drawShadow(outline, InsightTheme.ink.withValues(alpha: 0.12), 4, false);
    canvas.drawPath(outline, Paint()..color = Color.lerp(InsightTheme.blueTint, InsightTheme.surface, 0.35)!);
    canvas.drawPath(outline, Paint()..color = InsightTheme.blue1.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ActivityFolderPainter oldDelegate) =>
      oldDelegate.tabs != tabs || oldDelegate.selected != selected || oldDelegate.headerHeight != headerHeight;
}

/// A single real-record preview. The entire surface, including the footer,
/// opens the selected category's existing history interaction.
class ActivityFolderPreview extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;
  final int historyCount;
  final VoidCallback onOpenHistory;

  const ActivityFolderPreview({
    super.key,
    required this.icon, required this.color, required this.title,
    required this.subtitle, required this.time, required this.historyCount,
    required this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    final timestamp = Text(time, style: InsightTheme.inter(12, c: InsightTheme.ink3));
    return Semantics(
      button: true,
      child: Material(
        color: InsightTheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
        onTap: onOpenHistory,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final trailingTime = constraints.maxWidth >= 260 && MediaQuery.textScalerOf(context).scale(12) <= 16;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(child: Container(
                      width: 36, height: 36, alignment: Alignment.center,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, size: 24, color: Color.lerp(color, InsightTheme.ink, 0.18)),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: InsightTheme.urbanist(15, w: FontWeight.w700, c: InsightTheme.ink, h: 1.25)),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(subtitle, style: InsightTheme.inter(12, c: InsightTheme.ink3)),
                        ],
                        if (!trailingTime && time.isNotEmpty) ...[const SizedBox(height: 4), timestamp],
                      ],
                    )),
                    if (trailingTime && time.isNotEmpty) ...[const SizedBox(width: 8), timestamp],
                  ],
                );
              }),
              const Divider(height: 17, thickness: 1, color: InsightTheme.line),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(child: Text(
                      historyCount == 0 ? 'View activities' : 'View $historyCount ${historyCount == 1 ? 'activity' : 'activities'}',
                      style: InsightTheme.inter(13, w: FontWeight.w600, c: InsightTheme.blue1, h: 1.3),
                    )),
                    const SizedBox(width: 8),
                    const ExcludeSemantics(child: Icon(Icons.arrow_forward_rounded, size: 18, color: InsightTheme.blue1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
