# FieldSync / Ribbon logo kit

Final polished version ng approved Ribbon design, with custom curved FieldSync lettering.
Ang **red site dot** at maliit na **site** label ay nasa loob ng fingerprint. May curved navigation arrow na sumusunod sa open channel papunta sa dot.

**Primary app icon: kasama ang buong custom FieldSync lettering, route arrow, red site dot, at site label.** Ito ang nasa `app-icons/`, Flutter launcher sources, at Android resources.

## Capstone context

This identity is for the Flutter/Android field-inspection component of iMAPS used by MPDO
Site Inspectors in Rosario, Batangas. Its rationale follows the updated objectives and
FieldSync-specific system description in your supplied manuscript. See
`docs/LOGO-RATIONALE.md` for the explanation and exact source pages.

## Start here

1. Open `renders/fieldsync-overview.png` para makita ang final logo at icon backgrounds.
2. Use `svg/fieldsync-logo.svg` para sa malaking branding placement.
3. Use `svg/fieldsync-logo-compact.svg` para sa mas maliit na header/login branding.
4. Use `app-icons/white/app-icon-white-1024.png` as the default square launcher source.
5. For the actual Flutter/Android app, start with `flutter/README.md`.

## Alin ang gagamitin?

| Placement | File | Reason |
| --- | --- | --- |
| Large logo / about page / presentation | `svg/fieldsync-logo.svg` | Complete fingerprint, interior site detail, and curved custom lettering. |
| App header / login branding | `svg/fieldsync-logo-compact.svg` | Same artwork and lettering, without the tiny site label. The route arrow and red dot remain. |
| In-app icon | `svg/fieldsync-symbol.svg` | Fingerprint, integrated pin, route arrow and red site dot; without the app name or tiny site label. For secondary UI use. |
| Large symbol with site detail | `svg/fieldsync-symbol-detailed.svg` | Interior route arrow, red site dot and site label retained, without the curved app name. |
| Phone / installed app launcher | `app-icons/white/` | Complete logo with custom FieldSync lettering, route arrow and red site dot on an opaque white square. |
| Alternate dark icon | `app-icons/navy/` | Complete white logo with a red site dot on navy. |
| PWA icon with system cropping | `app-icons/maskable/` | Extra safe-area spacing for different masks. |
| Browser tab | `web/favicon.svg` or `web/favicon.ico` | A reduced lower-whorl symbol for very small display. |
| Print / one-color use | `svg/fieldsync-logo-black.svg` | Solid black outlines. |
| Dark background | `svg/fieldsync-logo-white.svg` | White artwork with the red site accent and transparency. |

## Background recommendation

**Sa gray pages ninyo: transparent ang logo.** Hayaan ang actual page gray na lumabas sa likod nito.
Hindi kailangang maglagay ng gray rectangle sa logo file.

**Para sa launcher icon: white `#FFFFFF` ang default background**, with navy `#102D50` artwork and a red `#EF3B3B` site dot.
It gives the detailed fingerprint a clean, consistent field. May navy-background alternate rin.
Ang `#F2F3F5` sa previews ay sample gray lamang; hindi ito claim na iyon ang exact gray ng app ninyo.

## Totoong SVG ba?

Yes. The delivered SVG artwork is made of cubic Bézier paths and circles. The lettering is
outlined artwork, so no font needs to be installed. Walang PNG/JPG na naka-embed sa SVG.
Vector shapes remain crisp as they scale. Ang PNGs ay convenience exports mula sa vector masters.
Native app launchers and some platform pipelines still need raster or platform-specific assets,
so included ang PNG sizes at web icon examples.

## Ano ang na-polish?

- Converted the approved generated sample to smooth, editable vector outlines.
- Kept the fingerprint and custom lettering navy `#102D50`; made the destination dot red `#EF3B3B`.
- Moved the small site node and label into the upper-middle interior route.
- Removed the old marker from the outer edge.
- Preserved the fingerprint silhouette, integrated pin, and custom curved lettering.
- Normalized transparent margins, symbol centering, and square launcher padding.
- Added a curved navigation arrow that follows the fingerprint channel to the red destination.
- Included the complete FieldSync lettering and site detail in the primary app icon.
- Kept optional compact and symbol variants for secondary UI placements.

## Folder guide

| Folder | Contents |
| --- | --- |
| `svg/` | Editable transparent masters, white/black alternates, compact logo and symbol variants. |
| `png/transparent/` | Transparent logo, lettering, and symbol exports in several sizes. |
| `app-icons/` | Complete logo in opaque square PNGs, maskable exports, and matching SVG sources; includes the lettering and red site dot. |
| `flutter/` | Android-focused launcher config, copied branding assets, and SVG widget example. |
| `native/android/` | Vector adaptive icon resources and density PNG fallbacks. |
| `web/` | Optional favicon SVG/ICO, Apple touch icon, and web integration examples. |
| `renders/` | Presentation, gray/white/navy background previews, small-size and mask checks. |
| `docs/` | Color and size guidance, exact asset inventory, and technical notes. |

PNG filename numbers are the width in pixels. Logos preserve their portrait aspect ratio;
symbols and app icons are square. The exact dimensions are listed in `docs/ASSET-INVENTORY.md`.

## Important usage details

- Keep the aspect ratio: do not stretch the logo into a square.
- Use a detailed full logo at roughly 512px wide or larger when the tiny site label must be readable.
- For secondary UI branding, use the compact full logo at roughly 160px wide or larger; use the symbol below that.
- The primary launcher keeps the full custom FieldSync lettering, route arrow, red site dot and site label at every exported size, as requested. Detail naturally reduces at small screen sizes.
- Use the micro symbol at 16–32px. It is a size-specific derivative, not the primary app logo.
- Leave the supplied margins intact; add room around the logo when near text or controls.
- Launcher files have square corners. The system or platform applies its mask.
- White SVG/PNG files are transparent white artwork with a red site accent; view them on a dark background. Black files are one-color print alternatives.

The supplied README, SVG/PNG studies, and `renders.zip` were inspected as the packaging reference.
This kit follows that SVG + transparent PNG + renders + explanation approach, using the approved
Ribbon artwork. The earlier loop/wordmark studies are not mixed into the final logo.

This is an asset handoff. Flutter and web snippets are examples for the existing app. The actual app project was not supplied, so no app configuration was changed or compiled here.
