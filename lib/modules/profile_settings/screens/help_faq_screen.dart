import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/insight_theme.dart';
import '../models/faq_item.dart';
import '../models/faq_data.dart';
import '../widgets/faq_widgets.dart';

/// ==================================================================
/// SCREEN — INSPECTOR HELP & FAQ GUIDE
/// ==================================================================
class HelpFaqScreen extends StatefulWidget {
  const HelpFaqScreen({super.key});

  @override
  State<HelpFaqScreen> createState() => _HelpFaqScreenState();
}

class _HelpFaqScreenState extends State<HelpFaqScreen> {
  bool _isTagalog = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _selectedCategoryIndex;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FaqCategory> _getFilteredCategories() {
    List<FaqCategory> list = [];
    for (int i = 0; i < FaqData.categories.length; i++) {
      if (_selectedCategoryIndex != null && _selectedCategoryIndex != i) continue;
      final cat = FaqData.categories[i];
      if (_searchQuery.isEmpty) {
        list.add(cat);
      } else {
        final matchingItems = cat.items.where((item) {
          return (_isTagalog ? item.questionTl : item.questionEn).toLowerCase().contains(_searchQuery) ||
              (_isTagalog ? item.answerTl : item.answerEn).toLowerCase().contains(_searchQuery) ||
              (_isTagalog ? item.questionEn : item.questionTl).toLowerCase().contains(_searchQuery) ||
              (_isTagalog ? item.answerEn : item.answerTl).toLowerCase().contains(_searchQuery);
        }).toList();
        if (matchingItems.isNotEmpty) {
          list.add(FaqCategory(titleEn: cat.titleEn, titleTl: cat.titleTl, icon: cat.icon, items: matchingItems));
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
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(),
                _buildLanguageControl(),
                _buildSearchBar(),
                _buildCategoryChips(),
                const SizedBox(height: 8),
                Expanded(
                  child: filteredCategories.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                          physics: const BouncingScrollPhysics(),
                          itemCount: filteredCategories.length,
                          itemBuilder: (context, catIdx) =>
                              _buildCategorySection(filteredCategories[catIdx]),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          FaqGlassBackButton(onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isTagalog ? 'Tulong at FAQ' : 'Help & FAQ',
              style: InsightTheme.poppins(17, w: FontWeight.w700, ls: -0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: FaqLanguageSegmentControl(
        isTagalog: _isTagalog,
        onToggle: (tagalog) => setState(() => _isTagalog = tagalog),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: InsightTheme.line),
          boxShadow: const [
            BoxShadow(color: Color(0x04141628), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: InsightTheme.ink3, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                style: InsightTheme.inter(13.5, c: InsightTheme.ink),
                decoration: InputDecoration(
                  hintText: _isTagalog ? 'Maghanap ng tanong o paksa...' : 'Search questions or topics...',
                  hintStyle: InsightTheme.inter(13, c: InsightTheme.ink3),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(Icons.close_rounded, color: InsightTheme.ink3, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    // The chips are content-sized, and a horizontal viewport needs a BOUNDED
    // height, so the track scales with the text scale rather than wrapping the
    // ListView in an unbounded box (which throws during layout). Each chip also
    // drops its fixed vertical padding in favour of a minHeight.
    final chipHeight = MediaQuery.textScalerOf(context).scale(26).clamp(26, double.infinity);
    return SizedBox(
      height: chipHeight + 12,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: FaqData.categories.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final isSelected = isAll
              ? _selectedCategoryIndex == null
              : _selectedCategoryIndex == index - 1;

          final label = isAll
              ? (_isTagalog ? 'Lahat' : 'All')
              : (_isTagalog
                  ? FaqData.categories[index - 1].titleTl
                  : FaqData.categories[index - 1].titleEn);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedCategoryIndex = isAll ? null : index - 1;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: BoxConstraints(minHeight: chipHeight.toDouble()),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? InsightTheme.blue1 : InsightTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? InsightTheme.blue1 : InsightTheme.line,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: InsightTheme.blue1.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  style: InsightTheme.inter(
                    12,
                    w: isSelected ? FontWeight.w700 : FontWeight.w500,
                    c: isSelected ? Colors.white : InsightTheme.ink2,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: InsightTheme.surface2,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off_rounded, size: 28, color: InsightTheme.ink3),
            ),
            const SizedBox(height: 14),
            Text(
              _isTagalog ? 'Walang nahanap na katanungan' : 'No matching questions found',
              style: InsightTheme.urbanist(15, w: FontWeight.w700, c: InsightTheme.ink),
            ),
            const SizedBox(height: 6),
            Text(
              _isTagalog
                  ? 'Subukang maghanap ng ibang salita o piliin ang "Lahat" na kategorya.'
                  : 'Try searching with different keywords or switch back to "All".',
              textAlign: TextAlign.center,
              style: InsightTheme.inter(13, c: InsightTheme.ink2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(FaqCategory category) {
    final title = _isTagalog ? category.titleTl : category.titleEn;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(category.icon, size: 16, color: InsightTheme.blue1),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  title.toUpperCase(),
                  style: InsightTheme.jetBrains(11, w: FontWeight.w700, c: InsightTheme.blueInk, ls: 0.6),
                )),
              ],
            ),
          ),
          Material(
            // The ExpansionTile paints its background and ink on the nearest
            // Material, so the decorated card must be a Material itself —
            // otherwise the tap ripple stays invisible behind this background.
            color: InsightTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: InsightTheme.line),
            ),
            elevation: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                children: [
                  for (int i = 0; i < category.items.length; i++) ...[
                    FaqExpansionTile(
                      item: category.items[i],
                      isTagalog: _isTagalog,
                    ),
                    if (i != category.items.length - 1)
                      const Divider(height: 1, color: InsightTheme.line, indent: 16, endIndent: 16),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
