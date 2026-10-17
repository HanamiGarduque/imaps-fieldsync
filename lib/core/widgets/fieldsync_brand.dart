import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Which approved FieldSync artwork file to show.
enum FieldSyncBrandVariant {
  /// Navy artwork for light surfaces (`InsightTheme.bg` and `surface`).
  navy,

  /// The kit's actual white artwork for the deep-blue surfaces
  /// (`InsightTheme.blue2`). Not a color filter, deliberately: the red site
  /// dot inside the fingerprint must survive on dark backgrounds.
  white,

  /// Navy fingerprint-only artwork for the bare Quick Actions button.
  symbol,
}

/// The FieldSync brand mark, rendered from the approved logo kit's own SVG.
///
/// Every file is copied verbatim from `assets/icon/FieldSync-Logo-Kit` into
/// `assets/branding/`; nothing here redraws or substitutes the artwork. The
/// SVGs keep their intrinsic aspect ratio: give one a [height] and the width
/// follows (887 x 1115 for both lockups, 1024 x 1024 for the symbol).
///
/// The mark is decorative by default (matching the `excludeFromSemantics: true`
/// images it replaces); pass [semanticsLabel] to expose it to screen readers.
class FieldSyncBrand extends StatelessWidget {
  const FieldSyncBrand({
    super.key,
    this.variant = FieldSyncBrandVariant.navy,
    this.height,
    this.semanticsLabel,
  });

  static const String navyAsset = 'assets/branding/fieldsync-logo.svg';
  static const String whiteAsset = 'assets/branding/fieldsync-logo-white.svg';
  static const String symbolAsset = 'assets/branding/fieldsync-symbol.svg';

  final FieldSyncBrandVariant variant;
  final double? height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final String asset = switch (variant) {
      FieldSyncBrandVariant.navy => navyAsset,
      FieldSyncBrandVariant.white => whiteAsset,
      FieldSyncBrandVariant.symbol => symbolAsset,
    };
    return SvgPicture.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
      semanticsLabel: semanticsLabel,
      excludeFromSemantics: semanticsLabel == null,
    );
  }
}
