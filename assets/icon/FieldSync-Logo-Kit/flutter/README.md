# Flutter / Android handoff

The capstone describes FieldSync as a Flutter application installed on the Site Inspectors'
Android phones (supplied manuscript, PDF page 152 / printed page 80). This is the primary
integration route for this logo kit. The web icon files are optional companion assets.

## In-app SVG branding

1. Copy `assets/branding/` from this folder into the Flutter project.
2. Add a compatible `flutter_svg` dependency, for example with `flutter pub add flutter_svg`.
3. Merge the following entry into the existing `flutter:` section of `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/branding/
```

4. Use the example in `branding.example.dart`. The SVG is transparent, so the page's gray
   background remains visible. Use the compact logo for a small header; the detailed master
   is for larger placements where the interior site detail can be read.

## Android launcher: choose one route

### Option A: Flutter launcher generator

Copy `flutter_launcher_icons.example.yaml` into the Flutter project root, next to pubspec.yaml.
The asset paths in the config assume the assets folder has been copied as described above.
Use a package release compatible with the project's current Flutter/Dart SDK:

```sh
flutter pub add --dev flutter_launcher_icons
dart run flutter_launcher_icons -f flutter_launcher_icons.example.yaml
```

This sample generates Android icons. `ios: false` matches the documented deployed target.
If an iOS target is added separately, configure that platform in the existing project.
The 1024px opaque white launcher source is already supplied. It includes the full custom FieldSync lettering, route arrow, interior site label and red site dot. The adaptive foreground uses the same complete logo, with safe-area spacing.

The adaptive foreground has built-in safe-area padding. `adaptive_icon_foreground_inset: 0`
avoids adding padding twice. Background is solid white; the themed icon uses a separate
monochrome foreground with the same full logo geometry; the system applies its themed color.

### Option B: native Android resources

Copy the contents of `../native/android/res/` into `android/app/src/main/res/`.
These resources use the distinct name `ic_fieldsync`. Point the application icon entry to:

```xml
android:icon="@mipmap/ic_fieldsync"
```

If the project sets `android:roundIcon`, update it to the same resource. Adaptive icons are
provided for API 26+, monochrome for API 33+, with PNG density fallbacks. Choose this route
instead of generating the same resources with Option A.

## Scope of validation

SVG/PNG geometry, transparency, XML syntax and resource references were checked. The actual
Flutter project was not supplied here, so these integration examples have not been compiled
against its dependencies. Rebuild and inspect the launcher on the project's test device.

## Primary references

- [flutter_svg](https://pub.dev/packages/flutter_svg)
- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons)
- [Android adaptive icon guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)

Checked 17 October 2026.
