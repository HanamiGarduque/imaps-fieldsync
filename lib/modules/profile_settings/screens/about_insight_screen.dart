import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';
import '../../../core/widgets/fieldsync_brand.dart';
import '../../../core/services/app_info_service.dart';

class AboutInsightScreen extends StatelessWidget {
  const AboutInsightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
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
                  child: const FieldPageHeader(title: 'About iMAPS'),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: const FieldSyncBrand(height: 64),
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        header: true,
                        child: Text(
                          'iMAPS:FieldSync',
                          style: InsightTheme.urbanist(26),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppInfoService.aboutVersionString,
                        style: InsightTheme.inter(14, c: InsightTheme.ink3),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: InsightTheme.line),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 16),
                      // Display the dependency notices Flutter actually registers.
                      // Team credits, map-data attribution and institutional
                      // approval are separate release checks, not implied here.
                      OutlinedButton.icon(
                        onPressed: () => showLicensePage(
                          context: context,
                          applicationName: 'iMAPS:FieldSync',
                          applicationVersion: AppInfoService.aboutVersionString,
                        ),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('Open-source licenses'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          alignment: Alignment.centerLeft,
                          foregroundColor: InsightTheme.blueInk,
                          side: const BorderSide(color: InsightTheme.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: InsightTheme.line),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: Text(
                          'Map data and attribution',
                          style: InsightTheme.urbanist(18),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Map tiles and street data: © OpenStreetMap contributors. '
                        'OpenStreetMap data is available under the Open Database '
                        'License (ODbL).',
                        style: InsightTheme.inter(
                          13,
                          c: InsightTheme.ink2,
                          h: 1.5,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            try {
                              final opened = await launchUrl(
                                Uri.parse('https://www.openstreetmap.org/copyright'),
                                mode: LaunchMode.externalApplication,
                              );
                              if (!opened && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not open OpenStreetMap licensing information.'),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not open OpenStreetMap licensing information.'),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('OpenStreetMap licenses'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            alignment: Alignment.centerLeft,
                            foregroundColor: InsightTheme.blueInk,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Road-route guidance uses the community-hosted OSRM '
                        'demonstration service. It is intended for development '
                        'and testing, with no availability guarantee.',
                        style: InsightTheme.inter(
                          13,
                          c: InsightTheme.ink2,
                          h: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rosario municipal boundary reference: MPDO Rosario '
                        'via iMAPS. The overlay does not authorize or complete '
                        'an inspection.',
                        style: InsightTheme.inter(
                          13,
                          c: InsightTheme.ink2,
                          h: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Semantics(
                        header: true,
                        child: Text(
                          'Development credits',
                          style: InsightTheme.urbanist(18),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Developed by the iMAPS:FieldSync capstone project team. '
                        'This academic project supports documentation and '
                        'authorized field-workflow demonstrations. Official '
                        'institutional adoption and policy approval require '
                        'separate authorization.',
                        style: InsightTheme.inter(
                          13,
                          c: InsightTheme.ink2,
                          h: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
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
                      const SizedBox(height: 20),
                      const Divider(height: 1, color: InsightTheme.line),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: Text(
                          'Technologies & services',
                          style: InsightTheme.urbanist(18),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cloud services: Supabase supports authentication, cloud records, and synchronization.',
                        style: InsightTheme.inter(13, c: InsightTheme.ink2, h: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Push notifications: OneSignal is used for push messaging. Firebase Cloud Messaging (FCM) may provide Android notification delivery when configured.',
                        style: InsightTheme.inter(13, c: InsightTheme.ink2, h: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Offline storage: SQLite supports local database operations, with SQLCipher used for encrypted database storage.',
                        style: InsightTheme.inter(13, c: InsightTheme.ink2, h: 1.5),
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
