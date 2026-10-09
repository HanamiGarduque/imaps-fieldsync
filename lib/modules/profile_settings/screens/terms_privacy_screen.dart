import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/insight_theme.dart';
import '../../../core/widgets/field_form_widgets.dart';

class TermsPrivacyScreen extends StatefulWidget {
  final bool initialShowTerms;

  const TermsPrivacyScreen({super.key, this.initialShowTerms = true});

  @override
  State<TermsPrivacyScreen> createState() => _TermsPrivacyScreenState();
}

class _TermsPrivacyScreenState extends State<TermsPrivacyScreen> {
  late bool _showTerms;

  @override
  void initState() {
    super.initState();
    _showTerms = widget.initialShowTerms;
  }

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
                  child: const FieldPageHeader(title: 'Legal Information'),
                ),
                Expanded(
                  child: ListView(
                    key: ValueKey(_showTerms),
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      FieldSegmentedControl<bool>(
                        labels: const {true: 'Terms of Use', false: 'Privacy Policy'},
                        value: _showTerms,
                        onChanged: (selection) {
                          HapticFeedback.selectionClick();
                          setState(() => _showTerms = selection);
                        },
                      ),
                      const SizedBox(height: 20),
                      _showTerms
                          ? _buildTermsContent()
                          : _buildPrivacyContent(),
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

  Widget _buildTermsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _HeaderSection(
          title: 'Terms and Conditions',
          date: 'September 7, 2026',
        ),
        SizedBox(height: 24),
        _PolicySection(
          title: '1. Authorized Use & Municipal Purpose',
          body:
              'Access to and use of this mobile platform are strictly restricted to authorized Zoning Officers and Administrative personnel of the Municipal Planning and Development Office (MPDO) of Rosario, Batangas. The application is an official municipal utility. Any use of this platform for personal or non-official purposes, or by unauthorized third parties, is strictly prohibited.',
        ),
        _PolicySection(
          title: '2. Zoning Inspection Activities & Data Capture',
          body:
              'iMAPS:FieldSync is an enterprise tool built to manage active zoning workloads, track field findings, and streamline inspection checklists. You are responsible for recording accurate GPS site verifications, capturing authentic site photographs, and submitting truthful checklist findings and recommendations for applicant parcels.',
        ),
        _PolicySection(
          title: '3. Offline-First Operation & Synchronization',
          body:
              'Evaluators acknowledge that the application caches records, media, and inspection actions locally on the secure device database during periods of limited or absent connectivity. It is the duty of the authorized officer to initiate and verify database synchronization once a stable connection to the Supabase network is established.',
        ),
        _PolicySection(
          title: '4. Authentication & Account Security',
          body:
              'You are responsible for maintaining the confidentiality of your account credentials and Quick Unlock passcodes. Do not share your access credentials or allow unverified individuals to operate the application on your behalf. Report security breaches immediately to the MPDO.',
        ),
        _PolicySection(
          title: '5. Confidentiality & Proper Use of Applicant/Site Data',
          body:
              'All applicant records, site metrics, boundary information, and inspection notes are confidential municipal records. Evaluators must ensure data accuracy and prevent unauthorized distribution of client data.',
        ),
        _PolicySection(
          title: '6. Access Revocation / Termination',
          body:
              'MPDO administration reserves the right to revoke account access at any time upon separation from the zoning task force, security compromise, or violation of these terms.',
        ),
        _PolicySection(
          title: '7. Governing Law',
          body:
              'These Terms are governed by and construed in accordance with the laws of the Republic of the Philippines, including applicable provisions of the Data Privacy Act of 2012.',
        ),
      ],
    );
  }

  Widget _buildPrivacyContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _HeaderSection(title: 'Privacy Policy', date: 'September 7, 2026'),
        SizedBox(height: 24),
        _PolicySection(
          title: '1. Information We Collect & Process',
          body:
              'To facilitate official zoning operations, iMAPS:FieldSync processes specific categories of operational data:\n\n'
              '• Inspector / account information\n'
              '• Applicant / application information\n'
              '• Site / parcel information\n'
              '• GPS / location information (GPS coordinates are captured during specific verification and inspection events)\n'
              '• Inspection photographs and geographic metadata (Field photographs captured through the application may contain geographic metadata used to support physical site verification and inspection records)\n'
              '• Inspection notes\n'
              '• Checklist answers\n'
              '• Findings\n'
              '• Discrepancy title / details\n'
              '• Recommendations\n'
              '• Task / scheduling information\n'
              '• Offline cached / encrypted local data\n'
              '• Pending actions / outbox\n'
              '• Supabase / cloud records\n'
              '• Supabase Storage objects\n'
              '• OneSignal / device notification information\n'
              '• Authentication / session information\n'
              '• Quick Unlock / offline passcode information',
        ),
        _PolicySection(
          title: '2. Use of Information & Offline Processing',
          body:
              'Collected information is used strictly to evaluate zoning applications, verify inspection sites, record findings, and synchronize secure records to the municipal Supabase backend. Local offline processing ensures uninterrupted fieldwork before syncing.',
        ),
        _PolicySection(
          title: '3. Authorized Access & Sharing',
          body:
              'Information is accessed solely by authorized MPDO personnel and municipal database administrators. Data is not shared with external commercial entities.',
        ),
        _PolicySection(
          title: '4. Storage, Security Safeguards & Retention',
          body:
              'Data is protected using encrypted local SQLite databases, secure storage mechanisms, and TLS-encrypted transmission channels. Records are retained for as long as required for municipal zoning administration.',
        ),
        _PolicySection(
          title: '5. Data Subject Rights & Privacy Inquiries',
          body:
              'In accordance with the Data Privacy Act of 2012, data subjects may inquire about stored records or request corrections. For inquiries, access requests, or issues regarding data privacy, contact the Rosario Municipal Planning and Development Office (MPDO) through the administrative desk or the official municipal communication channels.',
        ),
      ],
    );
  }
}

class _HeaderSection extends StatelessWidget {
  final String title;
  final String date;

  const _HeaderSection({required this.title, required this.date});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: InsightTheme.urbanist(24)),
        ),
        const SizedBox(height: 4),
        Text(
          'Effective date: $date',
          style: InsightTheme.inter(13, c: InsightTheme.ink3),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: InsightTheme.line),
      ],
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;

  const _PolicySection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: InsightTheme.urbanist(18)),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: InsightTheme.inter(14, c: InsightTheme.ink2, h: 1.7),
          ),
        ],
      ),
    );
  }
}
