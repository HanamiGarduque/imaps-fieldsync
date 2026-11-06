import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../models/faq_item.dart';
import '../models/faq_data.dart';
import '../widgets/faq_widgets.dart';
import 'reports_support_screen.dart';
import '../../interactive_guide/guide_host.dart';
import '../../interactive_guide/guide_preferences.dart';
import '../../interactive_guide/guide_script.dart';
import '../../interactive_guide/screens/interactive_guide_screen.dart';

/// Public Help UI only; no account or business data is restored from this.
class HelpFaqSnapshot {
  const HelpFaqSnapshot(this.isTagalog, this.search, this.category, this.scrollOffset);
  final bool isTagalog;
  final String search;
  final int? category;
  final double scrollOffset;
}

class HelpGuideReplay extends GuideReplayRequest {
  const HelpGuideReplay(super.language, this.origin);
  final HelpFaqSnapshot origin;
}

class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key, this.origin, this.reopenGuide = false,
    this.initialGuideLanguage = GuideLanguage.english, this.hasPreviousOffer = false});
  final HelpFaqSnapshot? origin;
  final bool reopenGuide, hasPreviousOffer;
  final GuideLanguage initialGuideLanguage;

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  bool _isTagalog = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _selectedCategoryIndex;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final origin = widget.origin;
    _isTagalog = origin?.isTagalog ?? false;
    _searchController.text = origin?.search ?? '';
    _searchQuery = _searchController.text.trim().toLowerCase();
    _selectedCategoryIndex = origin?.category;
    _scrollController = ScrollController(initialScrollOffset: origin?.scrollOffset ?? 0);
    if (widget.reopenGuide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openGuide();
      });
    }
  }

  Future<void> _openGuide() async {
    final origin = HelpFaqSnapshot(_isTagalog, _searchController.text,
      _selectedCategoryIndex, _scrollController.hasClients ? _scrollController.offset : 0);
    final request = await Navigator.of(context).push<GuideReplayRequest>(MaterialPageRoute(
      builder: (_) => InteractiveGuideScreen(initialLanguage: widget.initialGuideLanguage,
        hasPreviousOffer: widget.hasPreviousOffer)));
    if (!mounted || request == null || !Navigator.of(context).canPop()) return;
    Navigator.of(context).pop(HelpGuideReplay(request.language, origin));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<FaqCategory> _getFilteredCategories() {
    List<FaqCategory> list = [];
    for (int i = 0; i < FaqData.categories.length; i++) {
      if (_selectedCategoryIndex != null && _selectedCategoryIndex != i) {
        continue;
      }
      final cat = FaqData.categories[i];
      if (_searchQuery.isEmpty) {
        list.add(cat);
      } else {
        final matchingItems = cat.items.where((item) {
          return (_isTagalog ? item.questionTl : item.questionEn)
                  .toLowerCase()
                  .contains(_searchQuery) ||
              (_isTagalog ? item.answerTl : item.answerEn)
                  .toLowerCase()
                  .contains(_searchQuery) ||
              (_isTagalog ? item.questionEn : item.questionTl)
                  .toLowerCase()
                  .contains(_searchQuery) ||
              (_isTagalog ? item.answerEn : item.answerTl)
                  .toLowerCase()
                  .contains(_searchQuery);
        }).toList();
        if (matchingItems.isNotEmpty) {
          list.add(
            FaqCategory(
              titleEn: cat.titleEn,
              titleTl: cat.titleTl,
              icon: cat.icon,
              items: matchingItems,
            ),
          );
        }
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final filteredCategories = _getFilteredCategories();
    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedContent(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: FieldPageHeader(title: _isTagalog ? 'Tulong at FAQ' : 'Help & FAQ'),
                ),
                Expanded(
                  child: ListView(
                    key: const ValueKey('help-faq-list'), controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FaqLanguageSegmentControl(
                          isTagalog: _isTagalog,
                          onToggle: (tagalog) =>
                              setState(() => _isTagalog = tagalog),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ListTile(key: const ValueKey('interactive-guide-entry'),
                        leading: const Icon(Icons.fingerprint_rounded, color: InsightTheme.blueInk),
                        title: Text('FieldSync Interactive Guide', style: InsightTheme.inter(14, w: FontWeight.w600)),
                        subtitle: Text(GuideLabels(_isTagalog ? GuideLanguage.tagalog : GuideLanguage.english).pageIntroduction,
                          style: InsightTheme.inter(13)),
                        trailing: const Icon(Icons.chevron_right_rounded), onTap: _openGuide),
                      const SizedBox(height: 16),
                      _buildSearchBar(),
                      const SizedBox(height: 12),
                      _buildCategoryChips(),
                      const SizedBox(height: 20),
                      if (filteredCategories.isEmpty)
                        _buildEmptyState()
                      else
                        for (final category in filteredCategories)
                          _buildCategorySection(category),
                      const SizedBox(height: 8),
                      _buildSupportCard(),
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

  Widget _buildSearchBar() {
    return Semantics(
      label: _isTagalog ? 'Maghanap sa gabay' : 'Search the guide',
      child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      child: TextField(
        controller: _searchController,
        onChanged: (value) =>
            setState(() => _searchQuery = value.trim().toLowerCase()),
        style: InsightTheme.inter(14, c: InsightTheme.ink),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: InsightTheme.surface2,
          hintText: _isTagalog ? 'Maghanap sa gabay' : 'Search the guide',
          hintStyle: InsightTheme.inter(14, c: InsightTheme.ink3),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: InsightTheme.ink3,
            size: 20,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: InsightTheme.ink3,
                    size: 20,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: InsightTheme.roundedSm,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: InsightTheme.roundedSm,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: InsightTheme.roundedSm,
            borderSide: const BorderSide(color: InsightTheme.blue1, width: 1.5),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int index = 0; index <= FaqData.categories.length; index++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Builder(builder: (context) {
                final selected = index == 0
                    ? _selectedCategoryIndex == null
                    : _selectedCategoryIndex == index - 1;
                return ChoiceChip(
                  label: Text(
                    index == 0
                        ? (_isTagalog ? 'Lahat' : 'All')
                        : (_isTagalog
                              ? FaqData.categories[index - 1].titleTl
                              : FaqData.categories[index - 1].titleEn),
                  ),
                  selected: selected,
                  showCheckmark: false,
                  labelStyle: InsightTheme.inter(
                    11.5,
                    w: selected ? FontWeight.w700 : FontWeight.w600,
                    c: selected ? InsightTheme.blueInk : InsightTheme.ink2,
                  ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  backgroundColor: InsightTheme.surface,
                  selectedColor: InsightTheme.blueTint,
                  side: BorderSide(
                    color: selected
                        ? InsightTheme.blue1.withValues(alpha: 0.34)
                        : InsightTheme.lineStrong,
                  ),
                  shape: const StadiumBorder(),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(
                      () =>
                          _selectedCategoryIndex = index == 0 ? null : index - 1,
                    );
                  },
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            _isTagalog
                ? 'Walang nahanap na katanungan'
                : 'No matching questions found',
            textAlign: TextAlign.center,
            style: InsightTheme.urbanist(16),
          ),
          const SizedBox(height: 8),
          Text(
            _isTagalog
                ? 'Subukang maghanap ng ibang salita o piliin ang "Lahat" na kategorya.'
                : 'Try different keywords or choose All topics.',
            textAlign: TextAlign.center,
            style: InsightTheme.inter(14),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(FaqCategory category) {
    final title = _isTagalog ? category.titleTl : category.titleEn;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        border: Border.all(color: InsightTheme.line),
        boxShadow: InsightTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: InsightTheme.surface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(category.icon, size: 16, color: InsightTheme.blueInk),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: InsightTheme.urbanist(14.5, w: FontWeight.w700),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: InsightTheme.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${category.items.length}',
                    style: InsightTheme.inter(10, w: FontWeight.w700, c: InsightTheme.ink3),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: InsightTheme.line),
          for (int i = 0; i < category.items.length; i++) ...[
            FaqExpansionTile(item: category.items[i], isTagalog: _isTagalog),
            if (i != category.items.length - 1)
              const Divider(height: 1, color: InsightTheme.line, indent: 14, endIndent: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildSupportCard() {
    return Material(
      color: InsightTheme.blueTint,
      shape: RoundedRectangleBorder(
        borderRadius: InsightTheme.roundedMd,
        side: BorderSide(color: InsightTheme.blue1.withValues(alpha: 0.16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ReportsSupportScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.help_outline_rounded, size: 20, color: InsightTheme.blueInk),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isTagalog ? 'May hindi mahanap na sagot?' : "Can't find an answer?",
                      style: InsightTheme.inter(12.5, w: FontWeight.w700, c: InsightTheme.blueInk),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _isTagalog
                          ? 'I-message ang MPDO support desk'
                          : 'Message the MPDO support desk',
                      style: InsightTheme.inter(11, c: InsightTheme.blueInk),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: InsightTheme.blueInk),
            ],
          ),
        ),
      ),
    );
  }
}
