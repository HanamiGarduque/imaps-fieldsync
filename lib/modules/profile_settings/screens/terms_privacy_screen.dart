import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/insight_theme.dart';

/// ==================================================================
/// SCREEN — TERMS & PRIVACY
/// ==================================================================
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
      body: Stack(
        children: [
          // Shrunk Premium Background Blobs

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // 1. TOP BAR (Reduced Padding & Font Size)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      _GlassBackButton(onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Legal Information',
                          style: InsightTheme.poppins(16, w: FontWeight.w700, ls: -0.3),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. PREMIUM SLIDING SEGMENTED CONTROL (Compact)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _PremiumSegmentControl(
                    isFirstSelected: _showTerms,
                    firstOption: 'Terms of Use',
                    secondOption: 'Privacy Policy',
                    onToggle: (isFirst) => setState(() => _showTerms = isFirst),
                  ),
                ),

                const SizedBox(height: 6),

                // 3. CONTENT SCROLL VIEW (Tighter Margins)
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _GlassCard(
                        child: AnimatedCrossFade(
                          firstChild: _buildTermsContent(),
                          secondChild: _buildPrivacyContent(),
                          crossFadeState: _showTerms ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                          duration: const Duration(milliseconds: 350),
                          sizeCurve: Curves.easeOutCubic,
                          firstCurve: Curves.easeOut,
                          secondCurve: Curves.easeOut,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ==================================================================
  /// TERMS AND CONDITIONS CONTENT
  /// ==================================================================
  Widget _buildTermsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          title: 'Terms and Conditions',
          date: 'September 7, 2026',
        ),
        const SizedBox(height: 18),
        _PolicySection(
          icon: Icons.gavel_rounded,
          title: '1. Authorized Use & Municipal Purpose',
          body: 'Access to and use of this mobile platform are strictly restricted to authorized Zoning Officers and Administrative personnel of the Municipal Planning and Development Office (MPDO) of Rosario, Batangas. The application is an official municipal utility. Any use of this platform for personal or non-official purposes, or by unauthorized third parties, is strictly prohibited.',
        ),
        _PolicySection(
          icon: Icons.business_center_rounded,
          title: '2. Zoning Inspection Activities & Data Capture',
          body: 'iMAPS:FieldSync is an enterprise tool built to manage active zoning workloads, track field findings, and streamline inspection checklists. You are responsible for recording accurate GPS site verifications, capturing authentic site photographs, and submitting truthful checklist findings and recommendations for applicant parcels.',
        ),
        _PolicySection(
          icon: Icons.sync_rounded,
          title: '3. Offline-First Operation & Synchronization',
          body: 'Evaluators acknowledge that the application caches records, media, and inspection actions locally on the secure device database during periods of limited or absent connectivity. It is the duty of the authorized officer to initiate and verify database synchronization once a stable connection to the Supabase network is established.',
        ),
        _PolicySection(
          icon: Icons.lock_person_rounded,
          title: '4. Authentication & Account Security',
          body: 'You are responsible for maintaining the confidentiality of your account credentials and Quick Unlock passcodes. Do not share your access credentials or allow unverified individuals to operate the application on your behalf. Report security breaches immediately to the MPDO.',
        ),
        _PolicySection(
          icon: Icons.verified_user_rounded,
          title: '5. Confidentiality & Proper Use of Applicant/Site Data',
          body: 'All applicant records, site metrics, boundary information, and inspection notes are confidential municipal records. Evaluators must ensure data accuracy and prevent unauthorized distribution of client data.',
        ),
        _PolicySection(
          icon: Icons.block_rounded,
          title: '6. Access Revocation / Termination',
          body: 'MPDO administration reserves the right to revoke account access at any time upon separation from the zoning task force, security compromise, or violation of these terms.',
        ),
        _PolicySection(
          icon: Icons.shield_rounded,
          title: '7. Governing Law',
          body: 'These Terms are governed by and construed in accordance with the laws of the Republic of the Philippines, including applicable provisions of the Data Privacy Act of 2012.',
          isLast: true,
        ),
      ],
    );
  }

  /// ==================================================================
  /// PRIVACY POLICY CONTENT
  /// ==================================================================
  Widget _buildPrivacyContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          title: 'Privacy Policy',
          date: 'September 7, 2026',
        ),
        const SizedBox(height: 18),
        _PolicySection(
          icon: Icons.data_usage_rounded,
          title: '1. Information We Collect & Process',
          body: 'To facilitate official zoning operations, iMAPS:FieldSync processes specific categories of operational data:\n\n'
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
          icon: Icons.analytics_rounded,
          title: '2. Use of Information & Offline Processing',
          body: 'Collected information is used strictly to evaluate zoning applications, verify inspection sites, record findings, and synchronize secure records to the municipal Supabase backend. Local offline processing ensures uninterrupted fieldwork before syncing.',
        ),
        _PolicySection(
          icon: Icons.share_rounded,
          title: '3. Authorized Access & Sharing',
          body: 'Information is accessed solely by authorized MPDO personnel and municipal database administrators. Data is not shared with external commercial entities.',
        ),
        _PolicySection(
          icon: Icons.security_rounded,
          title: '4. Storage, Security Safeguards & Retention',
          body: 'Data is protected using encrypted local SQLite databases, secure storage mechanisms, and TLS-encrypted transmission channels. Records are retained for as long as required for municipal zoning administration.',
        ),
        _PolicySection(
          icon: Icons.privacy_tip_rounded,
          title: '5. Data Subject Rights & Privacy Inquiries',
          body: 'In accordance with the Data Privacy Act of 2012, data subjects may inquire about stored records or request corrections. For inquiries, access requests, or issues regarding data privacy, contact the Rosario Municipal Planning and Development Office (MPDO) through the administrative desk or the official municipal communication channels.',
          isLast: true,
        ),
      ],
    );
  }
}

/// ==================================================================
/// COMPONENT WIDGETS
/// ==================================================================

class _HeaderSection extends StatelessWidget {
  final String title;
  final String date;

  const _HeaderSection({required this.title, required this.date});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: InsightTheme.urbanist(18, w: FontWeight.w700, c: InsightTheme.blueInk, ls: -0.3)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.update_rounded, size: 12, color: InsightTheme.ink3),
            const SizedBox(width: 4),
            Text('Effective Date: $date', style: InsightTheme.inter(12, w: FontWeight.w500, c: InsightTheme.ink3)),
          ],
        ),
      ],
    );
  }
}

class _PolicySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool isLast;

  const _PolicySection({
    required this.icon,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    // Reduced spacing and font sizes
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: InsightTheme.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x05000000), blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Icon(icon, size: 15, color: InsightTheme.blue1),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1),
                Text(title, style: InsightTheme.urbanist(14, w: FontWeight.w600, c: InsightTheme.ink)),
                const SizedBox(height: 4),
                Text(body, style: InsightTheme.inter(12.5, w: FontWeight.w400, c: InsightTheme.ink2, h: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumSegmentControl extends StatelessWidget {
  final bool isFirstSelected;
  final String firstOption;
  final String secondOption;
  final Function(bool) onToggle;

  const _PremiumSegmentControl({
    required this.isFirstSelected,
    required this.firstOption,
    required this.secondOption,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // minHeight, not height: a fixed 44 left the language labels only 36px of
      // usable height, which centre-clipped them at a larger text scale.
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x05141628), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Stack(
        children: [
          // Animated Background Pill
          AnimatedAlign(
            alignment: isFirstSelected ? Alignment.centerLeft : Alignment.centerRight,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: InsightTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
                ),
              ),
            ),
          ),
          // Text Buttons Overlay
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onToggle(true);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: InsightTheme.inter(
                        12, // Shrunk text
                        w: isFirstSelected ? FontWeight.w600 : FontWeight.w500,
                        c: isFirstSelected ? InsightTheme.blueInk : InsightTheme.ink3,
                      ),
                      child: Text(firstOption),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onToggle(false);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: InsightTheme.inter(
                        12, // Shrunk text
                        w: !isFirstSelected ? FontWeight.w600 : FontWeight.w500,
                        c: !isFirstSelected ? InsightTheme.blueInk : InsightTheme.ink3,
                      ),
                      child: Text(secondOption),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    // Reduced border radius from 28 to 20, reduced padding
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x04141628), blurRadius: 12, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x08141628), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22), // Shrunk padding
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2), // Shrunk border width
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GlassBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x08141628), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: InsightTheme.ink), // Shrunk icon
              ),
            ),
          ),
        ),
      ),
    );
  }
}
