# Android production APK

Production uses `com.example.imaps_fieldsync`, the `prod` flavor and
`lib/main.dart`. Demo profile/release remain disabled. No phone is needed to
build; building does not install, sync, uninstall or clear application data.

## F-02 production signing

The owner authorized a **new permanent production signer**, not recovery of an
old key. The Gradle release configuration has no debug-signing fallback. It
requires an external keystore, valid private-key credentials and this public
certificate SHA-256 pin:

`9963e98109a4cac056af70374fe57120d440cf1b88258694d6aacf6500225dac`

Changing that identity requires a reviewed source change. Do not generate a new
key for subsequent releases. This APK is not guaranteed to update an old app
signed with a different certificate; never uninstall such an app to work around
that error without first verifying preservation of its offline records.

Keep the keystore and a Java properties file in private, persistent storage
outside the repository. The properties contain `storeFile` (an absolute path),
`keyAlias`, `storePassword` and `keyPassword`. Supply the file path through
`FIELDSYNC_PROD_SIGNING_PROPERTIES`; ignored `android/key.properties` is the
local fallback. Never put credentials in Dart defines, assets, Git or logs.

The generated local credentials are under `%USERPROFILE%\.fieldsync-signing`,
restricted to the current Windows user and SYSTEM. **Make an encrypted,
off-device backup of the entire directory.** No off-device backup is implied
by generating a key, and the private key cannot be recovered from an APK.

## Checks and build

Use the installed JDK and the existing locked dependencies. For example:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:FIELDSYNC_PROD_SIGNING_PROPERTIES = "$env:USERPROFILE\.fieldsync-signing\production.properties"
python tool/check_prod_signing.py
flutter build apk --no-pub --release --flavor prod --target lib/main.dart
```

The Python check exercises the real Gradle task graph in dry-run mode: accepted
production signing, missing/malformed inputs, debug-certificate rejection,
repository-key rejection, QA target/define rejection, unchanged prod-debug
builds with broken release inputs, and rejection of release packaging that
excludes Flutter compilation to bypass validation. It does not compile or
install an APK. Do not blanket-run `test/`: `webhook_test.dart`
can contact a real backend. Run explicitly inspected offline-safe suites.

For the delivered APK, export the exact committed/pushed revision to a clean
build directory. Reuse installed package configuration and local Android SDK
paths; provide only the validated public client `.env` required by prod. Do not
copy unused logo archives, previews, caches or old APKs into that source export.
Keep signing inputs external. Record the commit, configuration hash, build
command, checks/limitations and artifact SHA-256 with the APK.

Verify the output with Android SDK `apksigner verify --print-certs` and APK
manifest inspection: expected package/version, non-debuggable application,
release native payload and the pinned certificate. A successful build is not
native biometric, screenshot-protection, TalkBack or production-device proof.

Official signing guidance:
https://developer.android.com/studio/publish/app-signing#secure-shared-keystore
