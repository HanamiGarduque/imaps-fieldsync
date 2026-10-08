import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/insight_theme.dart';
import '../models/faq_item.dart';
import '../models/faq_data.dart';
import '../widgets/faq_widgets.dart';

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
      backgroundColor: InsightTheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedContent(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const BackButton(color: InsightTheme.ink),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            _isTagalog ? 'Tulong at FAQ' : 'Help & FAQ',
                            style: InsightTheme.urbanist(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: FaqLanguageSegmentControl(
                          isTagalog: _isTagalog,
                          onToggle: (tagalog) =>
                              setState(() => _isTagalog = tagalog),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSearchBar(),
                      const SizedBox(height: 12),
                      _buildCategoryChips(),
                      const SizedBox(height: 24),
                      if (filteredCategories.isEmpty)
                        _buildEmptyState()
                      else
                        for (final category in filteredCategories)
                          _buildCategorySection(category),
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
    return TextField(
      controller: _searchController,
      onChanged: (value) =>
          setState(() => _searchQuery = value.trim().toLowerCase()),
      style: InsightTheme.inter(14, c: InsightTheme.ink),
      decoration: InputDecoration(
        labelText: _isTagalog ? 'Maghanap sa gabay' : 'Search the guide',
        labelStyle: InsightTheme.inter(14, c: InsightTheme.ink3),
        hintText: _isTagalog ? 'Tanong o paksa' : 'Question or topic',
        hintStyle: InsightTheme.inter(14, c: InsightTheme.ink3),
        hintMaxLines: 2,
        prefixIcon: const Icon(Icons.search_rounded, color: InsightTheme.ink3),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, color: InsightTheme.ink3),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: InsightTheme.roundedSm,
          borderSide: const BorderSide(color: InsightTheme.lineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: InsightTheme.roundedSm,
          borderSide: const BorderSide(color: InsightTheme.lineStrong),
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
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  index == 0
                      ? (_isTagalog ? 'Lahat' : 'All')
                      : (_isTagalog
                            ? FaqData.categories[index - 1].titleTl
                            : FaqData.categories[index - 1].titleEn),
                ),
                selected: index == 0
                    ? _selectedCategoryIndex == null
                    : _selectedCategoryIndex == index - 1,
                showCheckmark: false,
                labelStyle: InsightTheme.inter(
                  13,
                  w: FontWeight.w500,
                  c: InsightTheme.ink2,
                ),
                backgroundColor: InsightTheme.surface,
                selectedColor: InsightTheme.blueTint,
                side: const BorderSide(color: InsightTheme.lineStrong),
                shape: RoundedRectangleBorder(
                  borderRadius: InsightTheme.roundedSm,
                ),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(
                    () =>
                        _selectedCategoryIndex = index == 0 ? null : index - 1,
                  );
                },
              ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              _isTagalog ? category.titleTl : category.titleEn,
              style: InsightTheme.urbanist(18),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in category.items) ...[
            FaqExpansionTile(item: item, isTagalog: _isTagalog),
            const Divider(height: 1, color: InsightTheme.line),
          ],
        ],
      ),
    );
  }
}
