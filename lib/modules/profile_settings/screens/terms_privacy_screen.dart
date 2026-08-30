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
          Positioned(
            top: -60, right: -40,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue1.withOpacity(0.18)),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -60,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(shape: BoxShape.circle, color: InsightTheme.blue2.withOpacity(0.12)),
              ),
            ),
          ),

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
          date: 'July 20, 2026',
        ),
        const SizedBox(height: 18),
        _PolicySection(
          icon: Icons.gavel_rounded,
          title: '1. Acceptance of Terms',
          body: 'By accessing and using the iMAPS:FieldSync application, you agree to comply with these Terms and Conditions. This application is designated exclusively for authorized Zoning Officers and Administrative personnel.',
        ),
        _PolicySection(
          icon: Icons.business_center_rounded,
          title: '2. Official Use Only',
          body: 'iMAPS:FieldSync is an enterprise tool built to manage active zoning workloads, track field findings, and streamline the inspection checklist process. Unauthorized distribution or personal use of this software is strictly prohibited.',
        ),
        _PolicySection(
          icon: Icons.verified_user_rounded,
          title: '3. Data Integrity',
          body: 'As an inspector, you are responsible for ensuring that all data captured—including photographic evidence, GPS verification points, and zoning checklist evaluations—is accurate and truthful to the best of your knowledge.',
        ),
        _PolicySection(
          icon: Icons.lock_person_rounded,
          title: '4. Account Security',
          body: 'You are responsible for maintaining the confidentiality of your account credentials. Do not share your Quick Unlock pattern with unverified individuals. Report any operational blockers or security breaches immediately to the MPDO.',
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
          date: 'July 20, 2026',
        ),
        const SizedBox(height: 18),
        _PolicySection(
          icon: Icons.data_usage_rounded,
          title: '1. Information We Collect',
          body: 'To facilitate field operations, iMAPS:FieldSync collects specific operational and personal data:\n\n'
                '• Profile Data: Full name, email address, and phone.\n'
                '• Location Data: Real-time GPS coordinates during verification.\n'
                '• Media: Site photos captured directly within the app.\n'
                '• Device Data: Offline cache status and sync logs.',
        ),
        _PolicySection(
          icon: Icons.analytics_rounded,
          title: '2. Use of Information',
          body: 'The collected data is utilized strictly for evaluating zoning applications, verifying inspection sites, and syncing accurate field findings to the main database via Supabase.',
        ),
        _PolicySection(
          icon: Icons.lock_outline_rounded,
          title: '3. Quick Unlock',
          body: 'If you opt-in to use the Quick Unlock feature, your pattern is stored as a salted hash, securely and locally on your device. The raw pattern is never stored or transmitted, and none of this data is sent to our servers.',
        ),
        _PolicySection(
          icon: Icons.shield_rounded,
          title: '4. Data Sharing & Retention',
          body: 'Information gathered through iMAPS:FieldSync is shared exclusively with the local MPDO database and authorized administrative users. All data processing conforms strictly to the Data Privacy Act of 2012 of the Philippines.',
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
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
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
              color: Colors.white.withOpacity(0.75),
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
          color: Colors.white.withOpacity(0.6),
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