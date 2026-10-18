import 'package:flutter/material.dart';

/// A single, independently navigable policy page.
///
/// The document body lives in a bundled markdown asset so the supplied draft
/// wording (DRAFT v0.9, prepared October 18, 2026) remains the source of
/// truth and can be replaced as a document instead of as code.
class PolicyDocument {
  const PolicyDocument({
    required this.menuLabel,
    required this.assetPath,
    required this.icon,
  });

  /// Label used on the profile menu row and in the page header. The formal
  /// document title is the `#` heading inside the markdown asset itself.
  final String menuLabel;

  /// Bundled markdown asset that holds the unabridged document body.
  final String assetPath;

  final IconData icon;
}

/// Terms & Conditions — 11 sections.
const termsAndConditionsDocument = PolicyDocument(
  menuLabel: 'Terms & Conditions',
  assetPath: 'assets/policies/terms_and_conditions.md',
  icon: Icons.gavel_rounded,
);

/// Privacy Notice — 13 sections. The menu row may say "Privacy Policy" while
/// the document keeps its formal title "Privacy Notice".
const privacyNoticeDocument = PolicyDocument(
  menuLabel: 'Privacy Policy',
  assetPath: 'assets/policies/privacy_notice.md',
  icon: Icons.shield_outlined,
);

/// Cookie & Storage Policy — 10 sections.
const cookieStoragePolicyDocument = PolicyDocument(
  menuLabel: 'Cookie & Storage Policy',
  assetPath: 'assets/policies/cookie_and_storage_policy.md',
  icon: Icons.cookie_outlined,
);
