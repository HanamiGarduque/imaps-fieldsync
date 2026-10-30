import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../../../core/widgets/fieldsync_brand.dart';
import '../../../core/widgets/sensitive_screen.dart';
import 'policy_documents.dart';

/// Shared page scaffold for the three separate policy documents.
///
/// Each policy is opened through its own route and renders its own document;
/// only the header, metadata card, notice styling and scrolling behaviour are
/// shared here.
class PolicyDocumentScreen extends StatelessWidget {
  const PolicyDocumentScreen({super.key, required this.document});

  final PolicyDocument document;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    // The owner-approved normal-app privacy matrix protects each policy
    // route, including when opened from an otherwise public Login screen.
    // The existing host secures the Android window before sensitive content
    // may paint; the original document layout and content are unchanged.
    return SensitiveScreen(
      child: Scaffold(
      backgroundColor: InsightTheme.bg,
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
                      Expanded(
                        child: FieldPageHeader(title: document.menuLabel),
                      ),
                      const SizedBox(width: 8),
                      const FieldSyncBrand(height: 40),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<String>(
                    future: rootBundle.loadString(document.assetPath),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'This document could not be loaded.',
                            style: InsightTheme.inter(14, c: InsightTheme.ink2),
                          ),
                        );
                      }
                      final source = snapshot.data;
                      if (source == null) return const SizedBox.shrink();
                      return ListView(
                        key: ValueKey(document.assetPath),
                        padding: const EdgeInsets.only(bottom: 32),
                        children: [
                          ...buildPolicyDocumentBody(source),
                          const _PolicyFooterBrand(),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Renders the constrained markdown subset used by the bundled policies:
/// `#`/`##` headings, `**bold**` runs, `> ` notices and `---` rules.
///
/// Bodies stay left-aligned on purpose: full justification leaves large
/// uneven gaps on narrow mobile widths.
List<Widget> buildPolicyDocumentBody(String markdown) {
  final blocks = <Widget>[];
  final metadata = <(String, String)>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(_PolicyParagraph(paragraph.join(' ')));
    paragraph.clear();
  }

  void flushMetadata() {
    if (metadata.isEmpty) return;
    blocks.add(_PolicyMetadataCard(rows: List.of(metadata)));
    metadata.clear();
  }

  final metadataPattern = RegExp(r'^\*\*(.+):\*\*\s*(.*)$');
  for (final rawLine in markdown.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      flushParagraph();
      continue;
    }
    final metadataLine = metadataPattern.firstMatch(line);
    if (line.startsWith('# ')) {
      flushParagraph();
      flushMetadata();
      blocks.add(_PolicyTitle(line.substring(2)));
    } else if (line.startsWith('## ')) {
      flushParagraph();
      flushMetadata();
      blocks.add(_PolicySectionHeading(line.substring(3)));
    } else if (line.startsWith('> ')) {
      flushParagraph();
      flushMetadata();
      blocks.add(_PolicyNoticeBox(line.substring(2)));
    } else if (line == '---') {
      flushParagraph();
      flushMetadata();
      blocks.add(const _PolicyRule());
    } else if (metadataLine != null && metadataLine.group(1) != 'Notice') {
      flushParagraph();
      metadata.add((metadataLine.group(1)!, metadataLine.group(2)!));
    } else if (metadataLine != null) {
      flushParagraph();
      flushMetadata();
      blocks.add(_PolicyFooterNotice(line));
    } else if (line.length > 4 &&
        line.startsWith('**') &&
        line.endsWith('**') &&
        !line.substring(2, line.length - 2).contains('**')) {
      flushParagraph();
      flushMetadata();
      blocks.add(_PolicySubtitle(line));
    } else {
      flushMetadata();
      paragraph.add(line);
    }
  }
  flushParagraph();
  flushMetadata();
  return blocks;
}

Widget _policyRichText(String text, TextStyle style) {
  final pattern = RegExp(r'\*\*(.+?)\*\*');
  final spans = <TextSpan>[];
  var index = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(text: text.substring(index, match.start)));
    }
    spans.add(
      TextSpan(
        text: match.group(1),
        style: style.copyWith(fontWeight: FontWeight.w700),
      ),
    );
    index = match.end;
  }
  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index)));
  }
  return Text.rich(
    TextSpan(style: style, children: spans),
    textAlign: TextAlign.start,
  );
}

class _PolicyTitle extends StatelessWidget {
  const _PolicyTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Semantics(
        header: true,
        child: Text(text, style: InsightTheme.urbanist(24)),
      ),
    );
  }
}

class _PolicySubtitle extends StatelessWidget {
  const _PolicySubtitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 16),
      child: _policyRichText(
        text,
        InsightTheme.inter(
          13,
          w: FontWeight.w600,
          c: InsightTheme.ink2,
          h: 1.5,
        ),
      ),
    );
  }
}

class _PolicyMetadataCard extends StatelessWidget {
  const _PolicyMetadataCard({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: InsightTheme.surface,
          borderRadius: BorderRadius.circular(InsightTheme.radiusMd),
          border: Border.all(color: InsightTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Text(
                rows[i].$1,
                style: InsightTheme.inter(
                  11,
                  w: FontWeight.w600,
                  c: InsightTheme.ink3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rows[i].$2,
                style: InsightTheme.inter(13, c: InsightTheme.ink2, h: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PolicyNoticeBox extends StatelessWidget {
  const _PolicyNoticeBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: InsightTheme.amberTint,
          borderRadius: BorderRadius.circular(InsightTheme.radiusSm),
        ),
        child: _policyRichText(
          text,
          InsightTheme.inter(13, c: InsightTheme.amberInk, h: 1.55),
        ),
      ),
    );
  }
}

class _PolicySectionHeading extends StatelessWidget {
  const _PolicySectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: InsightTheme.urbanist(18)),
      ),
    );
  }
}

class _PolicyParagraph extends StatelessWidget {
  const _PolicyParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _policyRichText(
        text,
        InsightTheme.inter(14, c: InsightTheme.ink2, h: 1.7),
      ),
    );
  }
}

class _PolicyRule extends StatelessWidget {
  const _PolicyRule();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 32, thickness: 1, color: InsightTheme.line);
  }
}

class _PolicyFooterNotice extends StatelessWidget {
  const _PolicyFooterNotice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _policyRichText(
        text,
        InsightTheme.inter(12, c: InsightTheme.ink3, h: 1.5),
      ),
    );
  }
}

class _PolicyFooterBrand extends StatelessWidget {
  const _PolicyFooterBrand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'iMAPS FieldSync · Municipal Planning and Development Office, '
        'Rosario, Batangas',
        textAlign: TextAlign.center,
        style: InsightTheme.inter(11, c: InsightTheme.ink3, h: 1.5),
      ),
    );
  }
}
