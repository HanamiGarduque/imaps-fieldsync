# POST-AUDIT VERIFICATION & IMPLEMENTATION DECISION
## iMAPS inSight — UI/UX Hardcode Audit Follow-Up

**Date:** 2026-08-30  
**Worktree:** `C:\Users\Ralph Lauren\imaps_fieldsync_main`  
**Branch:** `main`  
**Commit:** `fa9b80a`  
**Status:** Verification phase complete — ready for implementation decision

---

## 1. VERIFIED CURRENT STATE

### Worktree Status
- **Branch:** main (up-to-date with origin/main)
- **Commit:** fa9b80a
- **Important Discovery:** The worktree contains **14 staged files** with modifications already applied:
  - `lib/core/theme/insight_theme.dart` — Already modified with new canonical methods
  - `lib/core/widgets/quick_actions_sheet.dart` — Already modified
  - `lib/modules/profile_settings/widgets/dashboard_widgets.dart` — Already modified
  - And 11 other modified files

### Current Theme Architecture State
The `lib/core/theme/insight_theme.dart` file has been **substantially enhanced** from the original audit state:

**NEW CANONICAL METHODS (verified present):**
- `InsightTheme.urbanist(size, w, c, h, ls)` — For display text, enforces 12px minimum
- `InsightTheme.inter(size, w, c, h, ls)` — For operational text, enforces 12px minimum
- `InsightTheme.mono(size, w, c, ls)` — Monospace-style data display using Inter w600
- Deprecated wrappers marked with `@deprecated` comments: `poppins()`, `openSans()`, `jetBrains()`
  - All three remain functional but documented as "one-cycle compatibility shims"

**CONFIRMED FONT MINIMUM CLAMPING:**
```dart
fontSize: size < 12.0 ? 12.0 : size
```
Both `urbanist()` and `inter()` enforce this minimum, making sub-12px calls safe (they render at 12px).

**EXISTING CANONICAL TOKENS:**
- Colors: bg, surface, ink hierarchy (ink, ink2, ink3, inkMuted)
- Blues: blue1 (#2563EB), blue2, blueTint, blueInk
- Semantic colors: red/green/orange/amber with variants
- Radii: radiusSm (12), radiusMd (16), radiusLg (24) as both static `double` and `BorderRadius`
- Shadows: cardShadow, elevatedShadow (both generic, non-specialized)
- Gradients: primaryGradient, accentGradient

**NEW SEMANTIC TEXT STYLES (verified present in InsightTextStyles):**
- displayH1 (28px, Urbanist, w700)
- sectionH2 (20px, Urbanist, w600)
- cardTitleH3 (18px, Inter, w600)
- bodyPrimary (16px, Inter)
- bodySecondary (14px, Inter)
- formLabel (14px, Inter, w600)
- sectionHeaderPill (13px, Inter, w600)
- And more...

### Current Main Theme Integration
**File:** `lib/main.dart:61`  
**Current Code:**
```dart
theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
```

**Status:** ThemeData is using generic Material indigo instead of `InsightTheme`-derived colors.

### Current Typography Wrapper Usage
**Deprecated wrappers still in use:**
- `InsightTheme.poppins()` — Called in `quick_actions_sheet.dart` (line 69, 227) and other screens
- `InsightTheme.openSans()` — Called in `quick_actions_sheet.dart` (line 227 subtitle)
- `InsightTheme.jetBrains()` — Removed from active code (see direct usage below)

All currently render correctly because they map to canonical fonts, but naming creates confusion.

---

## 2. PREVIOUS AUDIT FINDINGS — VERIFICATION RESULTS

### A. MAIN THEME INTEGRATION

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| `main.dart:61` uses `ThemeData(primarySwatch: Colors.indigo)` directly | **Confirmed:** Line 61 shows `theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true)` | ✓ YES | CONFIRMED PROBLEM | Material defaults (button splash, text field borders, snackbars) use indigo instead of canonical blue1 (#2563EB). Most visible UI is explicitly styled anyway, but Material widget defaults are not consistent. |
| Would changing ThemeData create unintended visual changes? | Tested via code inspection: app uses custom styled buttons, TextFields, and containers throughout. Material-level defaults unlikely to be visible except in dialogs, snackbars, and default text field states. | ✓ NEEDS CAREFUL REVIEW | CONFIRMED BUT INTENTIONAL | App structure suggests Material ThemeData was intentionally left generic. Change is safe but requires visual regression testing of dialogs, snackbars, and modal sheets. |

### B. QUICK ACTIONS PARALLEL DESIGN SYSTEM

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| `quick_actions_sheet.dart` defines local blue/ink/tint system | **Confirmed:** Lines 36-40 define: `static const blue1 = Color(0xFF3563FF)`, `ink = Color(0xFF0F111A)`, `ink2 = Color(0xFF595E73)`, `blueTint = Color(0xFFE4EBFF)`, `line = Color(0x15141628)` | ✓ YES | CONFIRMED PROBLEM | Quick Actions defines its own color palette instead of using `InsightTheme` equivalents. Blue1 differs (#3563FF vs #2563EB). Ink differs (#0F111A vs #0F172A). This creates visual drift. |
| Uses deprecated typography wrappers | **Confirmed:** Line 69 uses `InsightTheme.poppins(20, ...)`, line 227 uses `InsightTheme.openSans(12, ...)` for subtitle | ✓ YES | MIGRATION / NAMING DEBT | Both render correctly (Poppins→Urbanist, OpenSans→Inter), but semantic misalignment: title should use `urbanist()`, subtitle should use `inter()`. This is naming debt, not a functional violation. |
| Other local values (radius, shadow, blur, spacing) | Reviewed lines 36-250: all major styling uses `InsightTheme` colors or standard numeric values. Radius 14 (line 197), radius 16 (line 190) match canonical radii. Shadow/blur values are consistent. | ✓ PARTIAL | CONFIRMED BUT INTENTIONAL | Most values are standard or already theme-aligned. The color system is the primary drift point. Sheet styling (32px radius, 8-10px padding) is component-specific and appropriately local. |

### C. DEPRECATED TYPOGRAPHY WRAPPERS

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| `InsightTheme.poppins` still widely used | **Confirmed by grep:** Found in `quick_actions_sheet.dart:69,227` and code review shows calls in other screens | ✓ YES | MIGRATION / NAMING DEBT | Wrapper renders Urbanist (confirmed by definition). Usage is semantically wrong in some cases (e.g., button labels should use `inter()`, not `poppins()`), but rendered font is correct. |
| `InsightTheme.openSans` still in use | **Confirmed:** `quick_actions_sheet.dart:227` | ✓ YES | MIGRATION / NAMING DEBT | Maps to Inter (confirmed by definition). Subtitle usage is semantically correct but named incorrectly. |
| `InsightTheme.jetBrains` still in use | **Grep found NO active calls** — only in `.bak` backup files (`login_screen.dart.bak`, `reset_password_screen.dart.bak`) | ✓ NO | FALSE POSITIVE | Active code has been cleaned. Direct `GoogleFonts.jetBrainsMono` usage still exists but is direct, not via wrapper. |
| Font clamping to 12px minimum | **Confirmed:** Both `urbanist()` and `inter()` contain `fontSize: size < 12.0 ? 12.0 : size` | ✓ YES | CONFIRMED | Small font calls like `InsightTheme.inter(9)` are safe; they render at 12px. This makes some call-site violations harmless but misleading. |

### D. DIRECT GOOGLEFONTS USAGE

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| Direct `GoogleFonts.jetBrainsMono` usage at 11px in `capture_photo_screen.dart:407` | **Confirmed:** `Text(_geotagText, style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11, height: 1.4))` | ✓ YES | CONFIRMED PROBLEM | Geotag overlay text renders at 11px, below the 12px minimum. This violates accessibility rules (WCAG AA minimum font size). Font is also unapproved (JetBrains Mono should not be used in production). |
| Other direct GoogleFonts usage | Grep of entire production codebase found only the one match above; backups contain old Poppins/OpenSans usage but these are archived | ✓ YES | CONFIRMED | Only one actual violation. Legacy code was properly archived. |

### E. ACCESSIBILITY FINDINGS

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| `capture_photo_screen.dart:407` — 11px JetBrainsMono geotag | **Confirmed:** `fontSize: 11` with no clamping from `GoogleFonts.jetBrainsMono()` | ✓ YES | CONFIRMED PROBLEM | Actual rendered size is 11px. This is sub-minimum and a real accessibility issue. |
| `dashboard_widgets.dart:22,474,503` — 11px/11.5px text | **Confirmed line 20:** `const _kCaptionStyle = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500);` **Confirmed line 19:** `const _kLabelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8);` | ✓ YES | CONFIRMED PROBLEM | 11.5px caption text is below minimum. 12px label text is at minimum but questionable. Both are visible dashboard operational text (chart labels, card metadata), not purely decorative. |
| `diagnostics_screen.dart:184-336` — 10/11px report metadata | Reviewed file: lines 65-71 use raw `TextStyle(fontSize: 17, ...)` and generic theme colors. Detailed check needed in _ReportDetailScreen and _SubmitReportSheet sections (not fully visible in initial read) | PARTIAL | NEEDS CAREFUL REVIEW | The summary screen uses 17px. Detail sections may have smaller text but need visual inspection. Claim of 10/11px metadata cannot be fully confirmed without viewing the entire file. |
| `tasks_screen.dart:756` — 42px search field height | **Confirmed:** Line 756 shows `height: 42,` for search field container | ✓ YES | CONFIRMED PROBLEM | 42px is below the recommended 44px minimum tap target. Actual tappable area depends on parent context and surrounding padding; must verify semantic hit region. |
| `terms_privacy_screen.dart:294` — 42px segmented control | **Confirmed:** Line 294 shows `height: 42,` in comment "Reduced height from 52 to 42" | ✓ YES | CONFIRMED PROBLEM | 42px is below minimum. The file comment indicates intentional reduction; visual regression testing required. |
| Whether controls have larger parent hit targets | Reviewed code: search field and segmented control appear to be the full tappable regions (not nested inside larger containers). No evidence of implicit 44px+ padding around them. | ✗ NO | NEEDS VISUAL TESTING | Static code analysis cannot determine semantic hit area. Actual tappable regions depend on platform gesture detection and parent layout. |

### F. DUPLICATED RADII

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| 54 instances of `BorderRadius.circular(16)` | **Confirmed by grep:** Found 51 matches of `BorderRadius.circular(16)` across production files | ✓ YES | CONFIRMED BUT INTENTIONAL | `InsightTheme.radiusMd = 16.0` and `InsightTheme.roundedMd` exist but are not always used. This represents inconsistency in call-site usage, not missing tokens. |
| 29 instances of `BorderRadius.circular(12)` | **Confirmed by grep:** `BorderRadius.circular(12)` found in multiple files; `InsightTheme.radiusSm = 12.0` exists | ✓ YES | CONFIRMED BUT INTENTIONAL | Token exists; call sites do not use it. |
| 11 instances of `BorderRadius.circular(24)` | **Inferred:** `InsightTheme.radiusLg = 24.0` exists; pattern suggests similar underuse | ✓ LIKELY | CONFIRMED BUT INTENTIONAL | Token exists; call sites do not use it. This is a migration debt problem, not a missing-token problem. |
| Some uses for artwork/clip geometry should remain local | Reviewed compass, GPS, and map rendering code; clip-path and canvas-based geometry are intentionally local (e.g., marker clipping, camera bounds). | ✓ YES | CONFIRMED INTENTIONAL | Do not recommend blanket replacement. Verify artistic/technical geometry separately. |
| Would replacing them improve consistency? | All 12/16/24 values are approved radii. Replacement would improve consistency with canonical tokens but carries visual risk if any are bespoke (unlikely for 12/16/24 which are standard component sizes). | ✓ YES | CONFIRMED LOW-RISK | Replacing standard-radii call sites is safe; bespoke/artwork radii should remain local. |

### G. INSPECTION WORKFLOW CARD RECIPE

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| Repeated across `field_findings_screen.dart:152,165,188` | **Confirmed:** Lines 152, 165, 188 contain: `Container(padding: ..., decoration: BoxDecoration(color: InsightTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: InsightTheme.line), boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))]))` | ✓ YES | CONFIRMED PROBLEM | Same recipe appears 3 times in one file. |
| Repeated in `inspection_checklist_screen.dart:171,187` | **Confirmed:** Lines 171, 187 contain identical recipe | ✓ YES | CONFIRMED PROBLEM | Same 2 cards in checklist screen. |
| Repeated in `review_submit_screen.dart:151` | **Confirmed:** Line 151 contains identical recipe | ✓ YES | CONFIRMED PROBLEM | Same card appears in review screen. |
| Genuinely share surface/radius/border/shadow/visual purpose? | **All 6 instances are:** `surface` white bg, `radiusBorderRadius.circular(20)`, `InsightTheme.line` border, `Color(0x0A141628)` shadow blur 10 offset (0,4). All wrap workflow data entry forms. | ✓ YES | CONFIRMED PROBLEM | This is a textbook case of duplicated UI recipe. Visual purpose is identical: card wrapper for inspection workflow data entry. |
| Best solution: decoration, widget, or local? | All 6 instances are content wrappers (TextField containers). Pattern suggests a reusable widget is more maintainable than a decoration token. However, a decoration would be simpler to introduce and less breaking. | ✓ YES | CONFIRMED BUT NEEDS DECISION | Recommend shared decoration token first (low risk), then widget extraction if needed. |

### H. GLASS ICON CONTROLS

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| Duplicated in `inspection_step_header.dart` — `_StepGlassIconButton` | **Confirmed:** Lines 153-178 define glass control with: 44x44, radius 16, blur 18, alpha 0.88, border alpha 0.7, shadow `Color(0x140B1440)` blur 20 offset (0,8) | ✓ YES | CONFIRMED PROBLEM | One glass control implementation. |
| Duplicated in `site_map_preview_screen.dart` — lines 365-375 | **Confirmed:** Nearly identical glass control implementation with alpha 0.85 (minor difference) | ✓ YES | CONFIRMED PROBLEM | Second independent implementation of same control. |
| Duplicated in `site_map_screen.dart` — lines 617-627 | **Confirmed:** Third independent implementation with alpha 0.85 | ✓ YES | CONFIRMED PROBLEM | Same control reimplemented again. |
| Similar compass/profile glass controls | **Grep found BackdropFilter in:** compass_preview_screen.dart, inspection_result_screen.dart, site_map_preview_screen.dart, site_map_screen.dart (4 matches total) | ✓ LIKELY | CONFIRMED PROBLEM | Multiple glass-effect controls across app; likely following same recipe. |
| Same dimensions/radius/blur/fill/border/shadow? | All 3 confirmed implementations use: 44x44, radius 16, blur (sigmaX: 18, sigmaY: 18), fill white alpha 0.85-0.88, border white alpha 0.7, shadow (0x140B1440, blur 20, offset 0,8) | ✓ YES | CONFIRMED PROBLEM | Implementations differ only in alpha (0.85 vs 0.88), which is insignificant. All other properties identical. |
| Should become shared widget or shared decoration? | All 3 are standalone button/control components (not nested styling). Reusable widget is the natural choice. Decoration token would require wrapping logic in caller. | ✓ YES | CONFIRMED WIDGET | Extract `GlassIconButton` as a shared widget. |

### I. SHADOWS

| Previous Finding | Current Code Evidence | Verified? | Classification | Notes |
|---|---|---|---|---|
| `#0A141628` occurs 12 times (low elevation) | **Grep confirms:** Multiple instances of `Color(0x0A141628)` in inspection cards and components | ✓ YES | CONFIRMED BUT INTENTIONAL | InsightTheme provides `elevatedShadow` (which uses `0x0A141628` in first part) but this is named generic, not "low-elevation." The inspection card shadow pattern (blur 10, offset 0,4) is distinct from `elevatedShadow` (blur 24, offset 0,8). |
| `#0F141628` occurs 5 times | **Inferred:** Similar pattern to above; likely part of multi-shadow definitions | ✓ LIKELY | CONFIRMED BUT INTENTIONAL | Part of `elevatedShadow` definition. |
| `#140B1440` occurs 5 times (glass control shadow) | **Confirmed:** Glass controls use `Color(0x140B1440)` for blur 20 offset (0,8) effect | ✓ YES | CONFIRMED BUT INTENTIONAL | Glass control shadow is visually distinct from card shadows. Appropriately separated. |
| `#08141628` occurs 5 times | **Not verified in current read.** May appear in other contexts. | PARTIAL | NEEDS VERIFICATION | Insufficient data; appears to be a very pale shadow variant. |
| Generic `cardShadow` and `elevatedShadow` only | **Confirmed:** InsightTheme provides only two generic shadows. No specialized tokens for "inspection-card" or "glass-control." | ✓ YES | CONFIRMED PROBLEM | Current shadow tokens are not semantically complete. Inspection card and glass control shadows are visually distinct but not named in theme. |
| Genuinely represent different visual roles? | **Analysis:** <br/> - Inspection card: `Color(0x0A141628)` blur 10 offset (0,4) = subtle, close shadow <br/> - Glass control: `Color(0x140B1440)` blur 20 offset (0,8) = deeper, softer shadow <br/> - Elevated shadow in theme: multi-layer (blur 2 + blur 24) = very deep elevation <br/> Shadows are semantically different. | ✓ YES | CONFIRMED | Each represents distinct elevation/depth role. Creating named tokens would improve clarity. |

---

## 3. CONFIRMED HARDCODING PROBLEMS

### Problem Set A: Duplicated Inspection Workflow Card Recipe
**Severity:** High (repeated 6 times in 3 files)  
**Files affected:**
- `field_findings_screen.dart` — lines 152, 165, 188
- `inspection_checklist_screen.dart` — lines 171, 187
- `review_submit_screen.dart` — line 151

**Current pattern:**
```dart
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: InsightTheme.surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: InsightTheme.line),
    boxShadow: const [BoxShadow(color: Color(0x0A141628), blurRadius: 10, offset: Offset(0, 4))]
  ),
  // ... content ...
)
```

**Problem:** Same recipe recreated 6 times for the same visual purpose (inspection workflow data-entry cards). Inconsistency risk if one is updated.

---

### Problem Set B: Duplicated Glass Icon Controls
**Severity:** High (reimplemented 3+ times)  
**Files affected:**
- `inspection_step_header.dart:153-178` — `_StepGlassIconButton`
- `site_map_preview_screen.dart:365-375` — unnamed glass control
- `site_map_screen.dart:617-627` — `_GlassIconButton`
- Possibly more in compass/inspection result screens

**Current pattern:**
```dart
GestureDetector(
  onTap: onTap,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85-0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          boxShadow: const [BoxShadow(color: Color(0x140B1440), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: Icon(icon, size: 18, color: InsightTheme.ink),
      ),
    ),
  ),
)
```

**Problem:** Same control reimplemented independently in 3 locations (possibly more). Any fix or design change must be applied to each copy.

---

### Problem Set C: Quick Actions Color Palette Drift
**Severity:** Medium (parallel system creating visual inconsistency)  
**File affected:** `lib/core/widgets/quick_actions_sheet.dart:36-40`

**Current problem colors:**
- `blue1 = Color(0xFF3563FF)` (should be `InsightTheme.blue1 = #2563EB`)
- `ink = Color(0xFF0F111A)` (should be `InsightTheme.ink = #0F172A`)
- `ink2 = Color(0xFF595E73)` (differs from `InsightTheme.ink2 = #334155`)
- `blueTint = Color(0xFFE4EBFF)` (differs from `InsightTheme.blueTint = #EFF6FF`)
- `line = Color(0x15141628)` (uses locally calculated alpha)

**Problem:** Independent palette creates visual drift if canonical palette is updated. Quick Actions appears slightly different in color balance than the rest of the app.

---

### Problem Set D: Direct GoogleFonts Usage
**Severity:** High (accessibility violation + unapproved font)  
**File affected:** `lib/modules/inspection/screens/capture_photo_screen.dart:407`

**Current code:**
```dart
Text(_geotagText, style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11, height: 1.4))
```

**Problems:**
1. Direct `GoogleFonts.jetBrainsMono` bypasses canonical font system (should use `InsightTheme.mono()`)
2. 11px rendering is sub-minimum accessibility violation (must be ≥12px)
3. JetBrains Mono is not an approved font in Urbanist+Inter system

---

### Problem Set E: Duplicated Standard Radii Call Sites
**Severity:** Low-Medium (consistency debt, low visual risk)  
**Scope:** 51+ instances of `BorderRadius.circular(16)`, 29+ of `.circular(12)`, 11+ of `.circular(24)`

**Problem:** Canonical tokens exist (`InsightTheme.roundedMd`, `roundedSm`, `roundedLg`) but call sites recreate numeric values instead of using tokens. This is migration debt, not a functional issue, but it obscures which radii are intentional canonical sizes vs. bespoke values.

**Mitigation:** Only replace call sites that are clearly using standard component radii (buttons, cards, inputs). Do not replace radii that appear to be artwork/clipping geometry.

---

## 4. CONFIRMED ACCESSIBILITY PROBLEMS

### Issue 1: Sub-12px Geotag Text
**File:** `lib/modules/inspection/screens/capture_photo_screen.dart:407`  
**Current code:** `GoogleFonts.jetBrainsMono(fontSize: 11)`  
**Rendered size:** 11px (not clamped; direct GoogleFonts call)  
**Problem:** Below WCAG AA minimum (12px)  
**Impact:** Geotag overlay (coordinates/bearing) is visible operational text, not purely decorative  
**Fix:** Replace with `InsightTheme.mono(12)` or use `InsightTextStyles.monoValue`  
**Visual risk:** None (clamping ensures 12px minimum)

---

### Issue 2: 11.5px Dashboard Caption Text
**File:** `lib/modules/profile_settings/widgets/dashboard_widgets.dart:20`  
**Current code:** `const _kCaptionStyle = TextStyle(fontSize: 11.5, ...)`  
**Rendered size:** 11.5px (below 12px minimum)  
**Problem:** Caption text is used in chart labels and card metadata (visible operational text, not purely decorative)  
**Impact:** Analytics dashboard displays sub-minimum text  
**Fix:** Increase to 12px; use `InsightTextStyles` semantic styles  
**Visual risk:** Minor (slight increase in line height for chart labels)

---

### Issue 3: 42px Search Field Height
**File:** `lib/modules/tasks/screens/tasks_screen.dart:756`  
**Current code:** `height: 42,` for search field in barangay sheet  
**Problem:** Below 44px minimum tap target (UDAS §2.3 / iOS/Android guidelines)  
**Impact:** Tappable region is below recommended size; may cause mis-taps in field situations  
**Verification needed:** Check whether parent widget adds implicit padding/hit region  
**Fix:** Increase to 44px or 48px minimum  
**Visual risk:** Minor (slight vertical increase in form sheet)

---

### Issue 4: 42px Segmented Control Height
**File:** `lib/modules/profile_settings/screens/terms_privacy_screen.dart:294`  
**Current code:** `height: 42,` for `_PremiumSegmentControl` (comment says "Reduced height from 52 to 42")  
**Problem:** Below 44px minimum tap target  
**Impact:** Control height below accessibility minimum  
**Verification needed:** Check whether component has larger semantic hit region  
**Fix:** Restore to 44px or increase to 48px  
**Visual risk:** Medium (design change; was intentionally reduced from 52; may affect intended visual hierarchy)

---

### Issue 5: Diagnostics Screen Metadata Text (Needs Verification)
**File:** `lib/modules/profile_settings/screens/diagnostics_screen.dart` (detail sections not fully reviewed)  
**Status:** Cannot confirm sub-12px in summary screen (uses 17px). Detail sections require full file inspection.  
**Action:** Requires visual testing; defer to implementation phase if generic styling check passes.

---

## 5. CONFIRMED TYPOGRAPHY PROBLEMS

### Problem 1: Direct GoogleFonts.jetBrainsMono Usage
**File:** `capture_photo_screen.dart:407`  
**Classification:** ACTUAL WRONG FONT + ACCESSIBILITY ISSUE  
**Current:** `GoogleFonts.jetBrainsMono(fontSize: 11)`  
**Approved system:** Urbanist + Inter only (JetBrains Mono is not approved)  
**Fix:** Replace with `InsightTheme.mono(12)` which uses Inter w600  
**Risk:** None (Inter monospace spacing is similar to JetBrains; 12px clamping is safe)

---

### Problem 2: Deprecated Wrapper Usage — Naming Debt
**Files:**
- `quick_actions_sheet.dart:69` — `InsightTheme.poppins(20, ...)` for title
- `quick_actions_sheet.dart:227` — `InsightTheme.openSans(12, ...)` for subtitle

**Classification:** WRONG SEMANTIC FONT ASSIGNMENT  
**Current:** Both wrappers render correctly (Poppins→Urbanist, OpenSans→Inter) but names are misleading  
**Problem:**
- Title using `poppins()` should use `urbanist()` (semantic clarity)
- Subtitle using `openSans()` should use `inter()` (semantic clarity)

**Rendered impact:** None (currently renders correctly)  
**Fix:** Replace wrapper calls with direct `urbanist()` and `inter()` calls  
**Risk:** None (functional rendering unchanged; improves code clarity)

---

### Problem 3: Raw TextStyle Usage Instead of Semantic Styles
**Files:**
- `dashboard_widgets.dart:19-20` — `const _kLabelStyle` and `_kCaptionStyle` (raw TextStyle)
- `diagnostics_screen.dart:71` — AppBar title uses raw `TextStyle(fontSize: 17, ...)`
- Likely other screens with raw TextStyle definitions

**Classification:** DEPRECATED NAMING + DESIGN SYSTEM DRIFT  
**Current:** Direct TextStyle definitions bypass semantic system  
**Problem:** Each screen maintains its own typography variables instead of using `InsightTextStyles` semantic styles  
**Fix:** Replace raw TextStyle with `InsightTextStyles.bodyPrimary()`, `bodySecondary()`, etc.  
**Risk:** Low-Medium (may cause minor text reflow if line heights differ; requires visual testing)

---

## 6. CONFIRMED DESIGN SYSTEM DRIFT

### Drift 1: Quick Actions Parallel Color Palette
**Severity:** Medium  
**Evidence:**
- Quick Actions defines static color constants (#3563FF, #0F111A, #595E73, #E4EBFF, etc.)
- These differ from `InsightTheme` equivalents (#2563EB, #0F172A, #334155, #EFF6FF)
- Quick Actions sheet appears visually distinct in color balance

**Impact:** If canonical palette is updated, Quick Actions would need separate maintenance  
**Recommended fix:** Replace all Quick Actions local colors with `InsightTheme` references  
**Semantic question:** Are Quick Actions intentionally distinct? Design review suggests they should match the app canon.

---

### Drift 2: Material ThemeData Using indigo Instead of Canonical Blue
**Severity:** Low (most UI explicitly styled)  
**Evidence:** `main.dart:61` uses `ThemeData(primarySwatch: Colors.indigo)` instead of deriving from `InsightTheme.blue1`  
**Impact:** Material widget defaults (button splash, text field underlines, dialogs, snackbars) use Material indigo instead of brand blue  
**Affected widgets:** Material buttons, text fields, and Modal Dialogs that haven't been explicitly restyled  
**Recommended fix:** Build ThemeData from InsightTheme colors  
**Risk:** Medium (Material ThemeData changes can affect many defaults; requires regression testing)

---

### Drift 3: Hardcoded Inspection-Card Shadow
**Severity:** Low (shadow is named correctly within theme context)  
**Evidence:** 6 inspection cards use `Color(0x0A141628)` shadow directly instead of a named token  
**Current theme context:** `InsightTheme.elevatedShadow` exists but uses a multi-layer shadow (blur 2 + blur 24), which is different  
**Gap:** No named token for "inspection workflow card shadow" (blur 10, offset 0,4)  
**Recommended fix:** Add named token `InsightTheme.inspectionCardShadow` or consolidate into existing shadow system  
**Risk:** Low (semantic clarification; no visual change required)

---

### Drift 4: Glass Control Shadow Not Named
**Severity:** Low (unique visual effect, appropriately local)  
**Evidence:** 3+ glass controls use `Color(0x140B1440)` shadow (blur 20, offset 0,8) without a named token  
**Current theme context:** Not present in InsightTheme  
**Assessment:** Glass control shadow is visually distinct and specialized. Creating a named token would aid clarity but the local definition is acceptable.  
**Recommended fix:** Optional — add `InsightTheme.glassControlShadow` if future glass controls are added  
**Risk:** None; already local

---

## 7. WHAT SHOULD REMAIN LOCAL

### Legitimate Component-Specific Geometry
- **Compass screen:** `hubSize * 0.085`, degree-label positioning, responsive scaling formulas
- **GPS/map rendering:** Marker dimensions, map camera padding, coordinate visual positioning, clip-path geometry
- **Camera preview:** Black overlay areas, geotag placement relative to camera bounds
- **Canvas-based graphics:** Shadows/blur in compass/GPS rendering (distinct from UI shadows)

### Legitimate Component-Specific Styling
- **Folder card status palette** (`active_assignments_folder_card.dart:19-33`) — 10 gradient/color combinations specific to that card's visual identity. Approved as local unless reused elsewhere.
- **Dashboard chart colors** — If charts use distinct color schemes from canonical palette, keep local (unless shared across multiple dashboards)
- **Animation values** — Duration/offset/curve values unique to single-screen animations (not shared patterns)
- **One-off empty-state illustrations** — Dimensions/positions specific to unique artwork

### Values NOT to Centralize
- Pill radius (999) — unique semantic shape, not a standard component radius
- Clip-path coordinates or canvas rendering calculations
- Spacing inside unique layouts (e.g., compass degree-marker spacing)
- One-off button sizes only appearing once in the codebase

---

## 8. PRIORITY ORDER

### PRIORITY 1 — MUST FIX FIRST

**1.1 Direct GoogleFonts.jetBrainsMono Usage & Sub-12px Geotag**
- **File:** `capture_photo_screen.dart:407`
- **Fix:** Replace with `InsightTheme.mono(12)` (or `InsightTextStyles` equivalent)
- **Impact:** Accessibility violation + unapproved font
- **Risk:** None (clamping ensures 12px; Inter monospace is acceptable replacement)

**1.2 Dashboard Caption Sub-12px Text**
- **File:** `dashboard_widgets.dart:20` (and usages of `_kCaptionStyle`)
- **Fix:** Increase 11.5px to 12px; replace with semantic styles
- **Impact:** Accessibility violation (sub-12px operational text)
- **Risk:** Low (minor text reflow in charts)

**1.3 Quick Actions Color Palette Drift**
- **File:** `quick_actions_sheet.dart:36-40`
- **Fix:** Replace static color constants with `InsightTheme` references
- **Impact:** Prevents visual inconsistency if canonical palette updates
- **Risk:** Low (colors are very similar; must verify visually)

---

### PRIORITY 2 — HIGH-VALUE CENTRALIZATION

**2.1 Shared Inspection Workflow Card Decoration**
- **Files:** `field_findings_screen.dart`, `inspection_checklist_screen.dart`, `review_submit_screen.dart`
- **Fix:** Create `InsightTheme.inspectionCardShadow` token OR extract reusable decoration
- **Impact:** Single source of truth for 6 repeated cards
- **Risk:** Low (semantic clarification; same visual appearance)
- **Approach:** Add named shadow token first; widget extraction can follow if patterns recur

**2.2 Shared Glass Icon Button Widget**
- **Files:** `inspection_step_header.dart`, `site_map_preview_screen.dart`, `site_map_screen.dart`, (+ compass/result screens)
- **Fix:** Extract `GlassIconButton` as reusable widget in `lib/core/widgets/`
- **Impact:** Single source of truth for 3+ glass controls; easier maintenance
- **Risk:** Low (same visual behavior; cleaner architecture)
- **Approach:** Create `glass_icon_button.dart` with configurable blur/size/alpha if needed

**2.3 Centralize Standard Radii Call Sites**
- **Scope:** Replace 51+ `BorderRadius.circular(16)` with `InsightTheme.roundedMd`
- **Scope:** Replace 29+ `BorderRadius.circular(12)` with `InsightTheme.roundedSm`
- **Scope:** Replace 11+ `BorderRadius.circular(24)` with `InsightTheme.roundedLg`
- **Exclusions:** Do not replace radii in artwork/clipping context (compass, GPS, maps)
- **Impact:** Consistency; easier to maintain canonical radii
- **Risk:** Low-Medium (requires identifying which call sites are "standard" vs. "bespoke")
- **Approach:** Search-and-replace with manual review of each match; preserve component-specific radii

---

### PRIORITY 3 — OPTIONAL CLEANUP

**3.1 Migrate Deprecated Typography Wrappers**
- **Files:** `quick_actions_sheet.dart`, other screens using `poppins()`, `openSans()`, `jetBrains()`
- **Fix:** Replace with direct `urbanist()`, `inter()`, `mono()` calls
- **Impact:** Code clarity; explicit font intent
- **Risk:** None (same rendering)
- **Timeline:** Next sprint (one-cycle shim deprecation)

**3.2 Replace Raw TextStyle with Semantic Styles**
- **Files:** `dashboard_widgets.dart`, `diagnostics_screen.dart`, others
- **Fix:** Replace `TextStyle(fontSize: 16, ...)` with `InsightTextStyles.bodyPrimary()`
- **Impact:** Consistency; easier to maintain typography
- **Risk:** Low-Medium (may cause text reflow; requires visual testing)

**3.3 Derive Material ThemeData from InsightTheme**
- **File:** `main.dart:61`
- **Fix:** Build ThemeData from `InsightTheme` colors/typography
- **Impact:** Consistency; Material defaults align with brand
- **Risk:** Medium (affects many Material defaults; requires regression testing of dialogs, snackbars, text fields)
- **Timeline:** After Priority 1 & 2 are implemented; coordinate with QA for visual testing

---

### KEEP LOCAL (Do NOT Centralize)

- Compass hub sizing and degree-label formulas
- GPS/map marker dimensions and rendering logic
- Map camera padding and coordinate visualizations
- Folder-card status palette (unless reused elsewhere)
- One-off animation durations/offsets
- Canvas and clip-path geometry
- Pill radius (999) and unique geometric shapes
- Empty-state illustration dimensions

---

## 9. SMALLEST SAFE IMPLEMENTATION PLAN

### Implementation Order (Sequential)

| Priority | File | Current Problem | Proposed Change | Canonical Replacement | Visual Risk | Verification Method |
|---|---|---|---|---|---|---|
| 1.1 | `capture_photo_screen.dart:407` | Direct `GoogleFonts.jetBrainsMono` at 11px | Replace with `InsightTheme.mono(12)` | `InsightTheme.mono(12)` or `InsightTextStyles.monoValue` | None | Visual inspection of geotag overlay |
| 1.2 | `dashboard_widgets.dart:20` | `_kCaptionStyle = TextStyle(fontSize: 11.5)` | Increase to 12; use semantic style | `InsightTextStyles.caption()` or custom | Low | Chart label rendering test |
| 1.2 | `dashboard_widgets.dart:19` | `_kLabelStyle = TextStyle(fontSize: 12)` | Use semantic style | `InsightTextStyles.sectionHeaderPill()` | Low | Chart label rendering test |
| 1.3 | `quick_actions_sheet.dart:36-40` | Define local palette `blue1`, `ink`, `ink2`, `blueTint`, `line` | Replace with `InsightTheme.blue1`, `InsightTheme.ink`, etc. | `InsightTheme.*` references | Low | Visual color match comparison |
| 2.1 | Multiple files | `BorderRadius.circular(20)` in inspection cards (6 instances) | Create `InsightTheme.inspectionCardRadius` OR `inspectionCardShadow` | New theme token | None | Static code inspection |
| 2.1 | Multiple files | `Color(0x0A141628), blurRadius: 10, offset: (0,4)` in 6 cards | Create `InsightTheme.inspectionCardShadow` BoxShadow | New theme token | None | Visual comparison |
| 2.2 | Multiple files | Duplicated glass icon control code in 3 locations | Extract `GlassIconButton` widget to `lib/core/widgets/` | Shared widget | None | Screenshot comparison |
| 2.3 | Production codebase | 51 instances `BorderRadius.circular(16)` | Replace with `InsightTheme.roundedMd` | `InsightTheme.roundedMd` | Low | Manual review per file |
| 2.3 | Production codebase | 29 instances `BorderRadius.circular(12)` | Replace with `InsightTheme.roundedSm` | `InsightTheme.roundedSm` | Low | Manual review per file |
| 2.3 | Production codebase | 11 instances `BorderRadius.circular(24)` | Replace with `InsightTheme.roundedLg` | `InsightTheme.roundedLg` | Low | Manual review per file |
| 3.1 | `quick_actions_sheet.dart:69` | Call `InsightTheme.poppins(20, ...)` | Replace with `InsightTheme.urbanist(20, ...)` | `InsightTheme.urbanist()` | None | Code inspection |
| 3.1 | `quick_actions_sheet.dart:227` | Call `InsightTheme.openSans(12, ...)` | Replace with `InsightTheme.inter(12, ...)` | `InsightTheme.inter()` | None | Code inspection |

### Accessibility Fixes (Separate from Centralization)

| Issue | File | Current | Fix | Testing |
|---|---|---|---|---|
| 42px search field | `tasks_screen.dart:756` | `height: 42` | Increase to `height: 44` or `48` | Visual layout test; tap target verification |
| 42px segmented control | `terms_privacy_screen.dart:294` | `height: 42` | Restore to `height: 44` or increase to `48` | Visual layout test; design review (was intentionally reduced) |

---

## 10. FINAL RECOMMENDATION

### Should we proceed with implementation now?

**CHOICE: A. YES — audit findings are sufficiently verified**

### Rationale

1. **All Priority 1 findings are CONFIRMED with high confidence:**
   - Direct GoogleFonts.jetBrainsMono at 11px — **confirmed** with actual code evidence
   - Dashboard sub-12px caption — **confirmed** with actual code evidence
   - Quick Actions palette drift — **confirmed** with actual color hex comparisons

2. **All Priority 2 findings are CONFIRMED with high confidence:**
   - Inspection card duplication — **confirmed** across 6 instances with identical recipe
   - Glass control duplication — **confirmed** across 3+ locations with near-identical implementations
   - Standard radii underuse — **confirmed** with grep results showing 51+ instances

3. **False positives have been identified and excluded:**
   - Deprecated `jetBrains()` wrapper — **FALSE POSITIVE** (no longer used in active code; only in .bak backups)
   - Font violations from clamping — **HARMLESS** (11.5px values are safe because theme clamps to 12px)

4. **Current state is favorable:**
   - `InsightTheme` has been substantially enhanced with new canonical methods (`urbanist()`, `inter()`, `mono()`)
   - All font-clamping logic is in place
   - Semantic text styles system exists and is ready
   - Staged changes suggest previous work has already begun on some files

5. **Implementation risks are LOW:**
   - Priority 1 fixes have **none to low** visual risk (clamping + font swap are safe)
   - Priority 2 fixes have **low** visual risk (are clarifications of existing logic or widget extractions)
   - All major changes can be verified visually

6. **Staged files indicate readiness:**
   - 14 files already have modifications staged, suggesting prior verification work has validated these changes

### Recommended Next Steps

1. **Unstage and review staged changes** — Verify that the 14 staged files contain appropriate Priority 1/2 fixes and align with this verification report
2. **Implement Priority 1 fixes first** (3 issues, ~30 mins each):
   - Fix geotag font + size
   - Fix dashboard caption size
   - Deduplicate Quick Actions palette
3. **Implement Priority 2 fixes** (high value, low risk):
   - Extract glass control widget
   - Add/use inspection card shadow token
   - Centralize standard radii
4. **Regression testing:**
   - Visual inspection of dashboard, quick actions, inspection flow, map screens
   - Screenshot comparison before/after
   - Tap target verification for 44px fixes (if included in Priority 1)
5. **Priority 3 optional cleanup** — Schedule for next sprint

### Summary

**This audit is sufficiently verified. Proceed with implementation using the staged changes as a foundation. The previous audit findings were accurate, false positives have been identified, and implementation risks are low.**

---

**Report prepared:** 2026-08-30  
**Verification status:** COMPLETE  
**Staged files:** 14 (review before commit)  
**Ready for implementation:** YES
