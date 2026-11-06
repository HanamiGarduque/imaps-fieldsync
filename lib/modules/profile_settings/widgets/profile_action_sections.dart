import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/insight_theme.dart';
import '../../interactive_guide/guide_targets.dart';
import '../screens/policy_documents.dart';

/// Content-sized expanded/compact identity; all inputs are display values.
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.avatarUrl,
    required this.initials,
    required this.displayName,
    required this.positionLabel,
    required this.userEmail,
    this.onEditTap,
    this.compact = false,
  });
  final String? avatarUrl;
  final String initials, displayName, positionLabel, userEmail;
  final VoidCallback? onEditTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final avatar = _Avatar(
      avatarUrl: avatarUrl,
      initials: initials,
      size: compact ? 44 : 48,
      fontSize: compact ? 16 : 18,
    );
    final edit = GuideTarget(id: 'profile_edit', child: Semantics(
      button: onEditTap != null,
      label: 'Edit profile',
      child: TextButton(
        key: const Key('profile-edit-button'),
        onPressed: onEditTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: 8,
          ),
          backgroundColor: compact ? null : InsightTheme.blueTint,
          foregroundColor: InsightTheme.blueInk,
          shape: RoundedRectangleBorder(borderRadius: InsightTheme.roundedSm),
        ),
        child: Flex(
          direction: compact ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline_rounded, size: 16),
            SizedBox(width: compact ? 0 : 4, height: compact ? 2 : 0),
            Text(
              'Edit',
              style: InsightTheme.inter(
                compact ? 12 : 13,
                w: FontWeight.w600,
                c: InsightTheme.blueInk,
              ),
            ),
          ],
        ),
      ),
    ));
    final email = Text(
      userEmail,
      style: InsightTheme.inter(compact ? 12 : 13, c: InsightTheme.ink2),
    );
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayName,
          key: const Key('profile-visible-name'),
          style: InsightTheme.urbanist(compact ? 14 : 16, w: FontWeight.w700),
        ),
        SizedBox(height: compact ? 2 : 4),
        if (compact)
          Text(
            positionLabel,
            style: InsightTheme.inter(12, c: InsightTheme.blueInk),
          )
        else
          Container(
            key: const Key('profile-role-badge'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: InsightTheme.blueTint,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: InsightTheme.blue1.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              positionLabel.toUpperCase(),
              style: InsightTheme.mono(
                12,
                w: FontWeight.w700,
                c: InsightTheme.blueInk,
                ls: 0.5,
              ),
            ),
          ),
        if (compact) ...[const SizedBox(height: 2), email],
      ],
    );
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: InsightTheme.surface,
        borderRadius: InsightTheme.roundedMd,
        boxShadow: kCardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inline =
              (compact &&
                  constraints.maxWidth >=
                      MediaQuery.textScalerOf(context).scale(240)) ||
              (constraints.maxWidth >= 280 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 20);
          if (compact) {
            final scrollableDetails = SingleChildScrollView(
              primary: false,
              child: details,
            );
            if (inline) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 12),
                  Expanded(child: scrollableDetails),
                  const SizedBox(width: 8),
                  edit,
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [avatar, const Spacer(), edit]),
                const SizedBox(height: 8),
                Flexible(child: scrollableDetails),
              ],
            );
          }
          return SingleChildScrollView(
            primary: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar,
                    const SizedBox(width: 12),
                    if (inline) Expanded(child: details) else const Spacer(),
                    if (!inline) ...[const SizedBox(width: 8), edit],
                  ],
                ),
                if (!inline) ...[const SizedBox(height: 8), details],
                const SizedBox(height: 8),
                const Divider(height: 1, color: InsightTheme.line),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.mail_outline_rounded,
                      size: 15,
                      color: InsightTheme.ink2,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: email),
                    if (inline) ...[const SizedBox(width: 8), edit],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.avatarUrl,
    required this.initials,
    this.size = 56,
    this.fontSize = 18,
  });
  final String? avatarUrl;
  final String initials;
  final double size, fontSize;

  @override
  Widget build(BuildContext context) {
    final radius = (size * 0.286).clamp(10.0, 18.0);
    final borderWidth = size > 44 ? 2.5 : 2.0;
    Widget fallback() => Center(
      child: Text(
        initials,
        style: InsightTheme.urbanist(
          fontSize,
          w: FontWeight.w800,
          c: Colors.white,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [InsightTheme.blue1, InsightTheme.blue2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: InsightTheme.blue1.withValues(alpha: 0.30),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.white, width: borderWidth),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          radius > borderWidth ? radius - borderWidth : radius,
        ),
        child: avatarUrl?.isNotEmpty == true
            ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, error, stack) => fallback(),
              )
            : fallback(),
      ),
    );
  }
}

/// Display-only groups; the normal Profile container supplies real destinations.
class ProfileActionSections extends StatelessWidget {
  const ProfileActionSections({
    super.key,
    required this.appVersion,
    this.onSecurity,
    this.onHelp,
    this.onSupport,
    this.onTerms,
    this.onPrivacy,
    this.onStorage,
    this.onAbout,
    this.onLogout,
  });
  final String appVersion;
  final VoidCallback? onSecurity,
      onHelp,
      onSupport,
      onTerms,
      onPrivacy,
      onStorage,
      onAbout,
      onLogout;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ProfileActionGroup(
        tiles: [
          ProfileActionTile(
            guideTargetId: 'profile_security',
            icon: Icons.fingerprint_rounded,
            title: 'Security & Protection',
            subtitle: 'Biometric login, auto-lock & protection',
            onTap: onSecurity,
          ),
          ProfileActionTile(
            guideTargetId: 'profile_help',
            icon: Icons.help_outline_rounded,
            title: 'Help & FAQ',
            subtitle: 'Guide, color codes & field rules',
            onTap: onHelp,
          ),
          ProfileActionTile(
            guideTargetId: 'profile_support',
            icon: Icons.flag_outlined,
            title: 'Support Desk',
            subtitle: 'Report a problem or an application concern',
            onTap: onSupport,
          ),
        ],
      ),
      const SizedBox(height: 12),
      ProfileActionGroup(
        tiles: [
          GuideTarget(id: 'profile_policies', child: Column(children: [
          ProfileActionTile(
            icon: termsAndConditionsDocument.icon,
            title: termsAndConditionsDocument.menuLabel,
            subtitle: 'Responsible use of iMAPS and FieldSync',
            onTap: onTerms,
          ),
          const Divider(height: 1, color: InsightTheme.line, indent: 50, endIndent: 16),
          ProfileActionTile(
            icon: privacyNoticeDocument.icon,
            title: privacyNoticeDocument.menuLabel,
            subtitle: 'How personal data is handled (Privacy Notice)',
            onTap: onPrivacy,
          ),
          const Divider(height: 1, color: InsightTheme.line, indent: 50, endIndent: 16),
          ProfileActionTile(
            icon: cookieStoragePolicyDocument.icon,
            title: cookieStoragePolicyDocument.menuLabel,
            subtitle: 'Cookies, sessions & device storage',
            onTap: onStorage,
          ),
          ])),
          ProfileActionTile(
            guideTargetId: 'profile_about',
            icon: Icons.info_outline_rounded,
            title: 'About iMAPS',
            subtitle: appVersion,
            onTap: onAbout,
          ),
        ],
      ),
      const SizedBox(height: 12),
      ProfileActionGroup(
        tiles: [
          ProfileActionTile(
            guideTargetId: 'profile_logout',
            icon: Icons.logout_rounded,
            title: 'Log Out',
            isDestructive: true,
            onTap: onLogout,
          ),
        ],
      ),
    ],
  );
}

class ProfileActionGroup extends StatelessWidget {
  const ProfileActionGroup({super.key, required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: InsightTheme.surface,
      borderRadius: InsightTheme.roundedMd,
      boxShadow: kCardShadow,
    ),
    child: Column(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          tiles[i],
          if (i != tiles.length - 1)
            const Divider(
              height: 1,
              color: InsightTheme.line,
              indent: 50,
              endIndent: 16,
            ),
        ],
      ],
    ),
  );
}

class ProfileActionTile extends StatelessWidget {
  const ProfileActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.isDestructive = false,
    this.onTap,
    this.guideTargetId,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDestructive;
  final VoidCallback? onTap;
  final String? guideTargetId;

  @override
  Widget build(BuildContext context) {
    final heading = Text(title, style: InsightTheme.urbanist(15, w: FontWeight.w600,
      c: isDestructive ? InsightTheme.red : InsightTheme.ink));
    final tile = InkWell(
    onTap: onTap == null
        ? null
        : () {
            HapticFeedback.lightImpact();
            onTap!();
          },
    borderRadius: InsightTheme.roundedMd,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: subtitle == null ? 8 : 12,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDestructive ? InsightTheme.red : InsightTheme.blueInk,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  heading,
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: InsightTheme.inter(12, c: InsightTheme.ink2),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: InsightTheme.ink3,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
    return guideTargetId == null ? tile : GuideTarget(id: guideTargetId!, child: tile);
  }
}
