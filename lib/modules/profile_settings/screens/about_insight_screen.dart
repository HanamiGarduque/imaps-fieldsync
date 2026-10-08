import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/services/app_info_service.dart';

class AboutInsightScreen extends StatelessWidget {
  const AboutInsightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
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
                            'About iMAPS',
                            style: InsightTheme.urbanist(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 16, bottom: 32),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          width: 64,
                          height: 64,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: Text(
                          'iMAPS:FieldSync',
                          style: InsightTheme.urbanist(26),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppInfoService.fullVersionString,
                        style: InsightTheme.inter(14, c: InsightTheme.ink3),
                      ),
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: InsightTheme.line),
                      const SizedBox(height: 24),
                      Text(
                        'The field inspection app for authorized MPDO and Zoning personnel in Rosario, Batangas.',
                        style: InsightTheme.inter(
                          16,
                          c: InsightTheme.ink,
                          h: 1.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Use FieldSync for site and GPS verification, inspection photos, zoning checklists, findings, and recommendations. Work offline in the field and synchronize records when a connection is available.',
                        style: InsightTheme.inter(
                          14,
                          c: InsightTheme.ink2,
                          h: 1.7,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Municipal Planning and Development Office (MPDO)',
                        style: InsightTheme.inter(
                          14,
                          w: FontWeight.w600,
                          c: InsightTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rosario, Batangas',
                        style: InsightTheme.inter(14, c: InsightTheme.ink3),
                      ),
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
