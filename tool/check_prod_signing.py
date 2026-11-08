"""Exercise the real Gradle signing/entry-point gate without compiling an APK.

Set JAVA_HOME and FIELDSYNC_PROD_SIGNING_PROPERTIES, then run this from the repo.
No signing secrets are printed, and no phone/backend is accessed.
"""

import base64
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    approved = Path(os.environ["FIELDSYNC_PROD_SIGNING_PROPERTIES"]).resolve()
    assert approved.is_file(), "Approved external signing properties are required."
    wrapper = ["cmd.exe", "/d", "/c", "gradlew.bat"] if os.name == "nt" else ["./gradlew"]
    with tempfile.TemporaryDirectory(
        prefix="fieldsync-signing-check-", dir=os.environ.get("FIELDSYNC_TEST_TMPDIR")
    ) as temporary:
        temporary = Path(temporary)
        init = temporary / "check-signer.gradle"
        init.write_text(
            """gradle.projectsEvaluated {
    def app = gradle.rootProject.findProject(':app')
    if (app == null) return
    def signing = app.extensions.getByName('android').buildTypes.getByName('release').signingConfig
    if (signing == null || signing.name != 'production') {
        throw new GradleException('prodRelease must use production signing, not a debug fallback')
    }
}
""",
            encoding="utf-8",
        )
        missing = temporary / "missing.properties"
        debug = temporary / "debug.properties"
        debug.write_text(
            f"storeFile={(Path.home() / '.android/debug.keystore').as_posix()}\n"
            "keyAlias=androiddebugkey\nstorePassword=android\nkeyPassword=android\n",
            encoding="ascii",
        )
        in_repo = temporary / "in-repository.properties"
        in_repo.write_text(
            f"storeFile={(root / 'android/app/not-a-release-key.jks').as_posix()}\n"
            "keyAlias=fixture\nstorePassword=fixture\nkeyPassword=fixture\n",
            encoding="ascii",
        )
        malformed = temporary / "malformed.properties"
        malformed.write_text("storeFile=bad\\uZZZZ\n", encoding="ascii")
        invalid_path = temporary / "invalid-path.properties"
        invalid_path.write_text(
            "storeFile=bad\\u0000path\nkeyAlias=fixture\n"
            "storePassword=fixture\nkeyPassword=fixture\n",
            encoding="ascii",
        )
        qa = base64.b64encode(b"QA_PREVIEW=true").decode("ascii")
        cases = [
            ("release cannot bypass validation by excluding Flutter compilation", [":app:assembleProdRelease", "-x", ":app:compileFlutterBuildProdRelease"], "lib/main.dart", "", debug, "requires compileFlutterBuildProdRelease"),
            ("malformed release inputs do not break debug", [":app:compileFlutterBuildProdDebug"], "lib/main.dart", "", malformed, None),
            ("invalid release path does not break debug", [":app:compileFlutterBuildProdDebug"], "lib/main.dart", "", invalid_path, None),
            ("malformed release inputs fail closed", [":app:compileFlutterBuildProdRelease"], "lib/main.dart", "", malformed, "production signing inputs"),
            ("approved production signer", [":app:compileFlutterBuildProdRelease"], "lib/main.dart", "", approved, None),
            ("missing credentials fail closed", [":app:compileFlutterBuildProdRelease"], "lib/main.dart", "", missing, "production signing inputs"),
            ("debug certificate rejected", [":app:compileFlutterBuildProdRelease"], "lib/main.dart", "", debug, "production signing certificate"),
            ("repository keystore rejected", [":app:compileFlutterBuildProdRelease"], "lib/main.dart", "", in_repo, "outside the repository"),
            ("QA entry point rejected", [":app:compileFlutterBuildProdRelease"], "lib/main_qa.dart", "", approved, "prod variants must target lib/main.dart"),
            ("QA define rejected", [":app:compileFlutterBuildProdRelease"], "lib/main.dart", qa, approved, "QA_PREVIEW=true must not be set"),
            ("prod debug needs no release credentials", [":app:compileFlutterBuildProdDebug"], "lib/main.dart", "", missing, None),
        ]
        for name, tasks, target, defines, inputs, rejection in cases:
            command = wrapper + tasks + [
                "--dry-run", "--offline",
                "--no-daemon", "--console=plain", "--init-script", str(init),
                f"-Ptarget={target}", f"-Pdart-defines={defines}",
                "-Dorg.gradle.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=384m -XX:+UseSerialGC",
            ]
            result = subprocess.run(
                command, cwd=root / "android", capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=600,
                env={**os.environ, "FIELDSYNC_PROD_SIGNING_PROPERTIES": str(inputs)},
            )
            output = result.stdout + result.stderr
            passed = result.returncode == 0 if rejection is None else result.returncode != 0 and rejection in output
            # Gradle can serialize a SigningConfig in unrelated exception output.
            # Never print raw child output or attempt to parse/redact passwords.
            assert passed, f"{name} failed (Gradle exit {result.returncode}; expected {rejection or 'success'}). Raw signing output withheld."
            print(f"PASS: {name}", flush=True)
    print(f"{len(cases)}/{len(cases)} real Gradle gate checks passed; no APK compiled or installed.")


if __name__ == "__main__":
    main()
