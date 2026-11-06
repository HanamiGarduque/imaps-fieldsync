import 'package:flutter/material.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../../../core/widgets/fieldsync_brand.dart';
import '../guide_host.dart';
import '../guide_preferences.dart';
import '../guide_script.dart';
import '../guide_targets.dart';

class InteractiveGuideScreen extends StatefulWidget {
  const InteractiveGuideScreen({
    super.key,
    required this.initialLanguage,
    required this.hasPreviousOffer,
    this.walkthrough = false,
  });
  final GuideLanguage initialLanguage;
  final bool hasPreviousOffer;
  final bool walkthrough;

  @override
  State<InteractiveGuideScreen> createState() => _InteractiveGuideScreenState();
}

class _InteractiveGuideScreenState extends State<InteractiveGuideScreen> {
  late GuideLanguage _language = widget.initialLanguage;
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final labels = GuideLabels(_language);
    Widget section(String heading, String body) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              heading,
              style: InsightTheme.urbanist(18, w: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: InsightTheme.inter(14)),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: InsightTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: FieldPageHeader(title: 'FieldSync Interactive Guide'),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('interactive-guide-copy'),
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GuideTarget(
                          id: 'guide_replay',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                labels.chooseLanguage,
                                style: InsightTheme.inter(
                                  14,
                                  w: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              FieldSegmentedControl<GuideLanguage>(
                                labels: const {
                                  GuideLanguage.tagalog: 'Filipino (Tagalog)',
                                  GuideLanguage.english: 'English',
                                },
                                value: _language,
                                onChanged: (value) =>
                                    setState(() => _language = value),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                key: const ValueKey('interactive-guide-start'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: InsightTheme.blue1,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(48, 48),
                                  padding: const EdgeInsets.all(12),
                                  textStyle: InsightTheme.inter(
                                    14,
                                    w: FontWeight.w600,
                                  ),
                                ),
                                onPressed: _starting || widget.walkthrough
                                    ? null
                                    : () {
                                        setState(() => _starting = true);
                                        Navigator.of(
                                          context,
                                        ).pop(GuideReplayRequest(_language));
                                      },
                                child: Text(
                                  widget.hasPreviousOffer
                                      ? labels.replay
                                      : labels.start,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                labels.replayLanguageNote,
                                style: InsightTheme.inter(13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: FieldSyncBrand(
                            variant: FieldSyncBrandVariant.symbol,
                            height: 48,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          labels.pageIntroduction,
                          style: InsightTheme.inter(14),
                        ),
                        section(labels.exploreHeading, labels.exploreBody),
                        section(labels.navigationHeading, labels.navigation),
                        section(labels.examplesHeading, labels.examplesBody),
                        const SizedBox(height: 12),
                        Text(labels.safety, style: InsightTheme.inter(14)),
                      ],
                    ),
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
