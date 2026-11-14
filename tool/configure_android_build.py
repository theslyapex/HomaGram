#!/usr/bin/env python3
"""Set HomaGram Android SDK levels and stable release signing."""
from pathlib import Path
import re
import sys


def main() -> int:
    candidates = [Path("android/app/build.gradle.kts"), Path("android/app/build.gradle")]
    gradle = next((p for p in candidates if p.exists()), None)
    if gradle is None:
        print("Android app Gradle file was not generated.", file=sys.stderr)
        return 1

    text = gradle.read_text(encoding="utf-8")
    kotlin = gradle.suffix == ".kts"

    if kotlin:
        dependency = '    implementation("com.squareup.okhttp3:okhttp:4.12.0")'
    else:
        dependency = "    implementation 'com.squareup.okhttp3:okhttp:4.12.0'"

    if "com.squareup.okhttp3:okhttp" in text:
        dependency_n = 1
    else:
        text, dependency_n = re.subn(
            r"(?m)^([ \t]*)dependencies\s*\{",
            lambda match: match.group(0) + "\n" + dependency,
            text, count=1)
        if dependency_n == 0:
            text = text.rstrip() + "\n\ndependencies {\n" + dependency + "\n}\n"
            dependency_n = 1

    if kotlin:
        text, compile_n = re.subn(r"(?m)^([ \t]*)compileSdk\s*=\s*[^\n]+", r"\g<1>compileSdk = 36", text, count=1)
        text, target_n = re.subn(r"(?m)^([ \t]*)targetSdk\s*=\s*[^\n]+", r"\g<1>targetSdk = 36", text, count=1)
        text, min_n = re.subn(r"(?m)^([ \t]*)minSdk\s*=\s*[^\n]+", r"\g<1>minSdk = 24", text, count=1)
        block = '''
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH"))
            storePassword = System.getenv("ANDROID_STORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
'''
        if 'create("release")' not in text:
            text, inserted = re.subn(r"(?m)^([ \t]*)buildTypes\s*\{", block + r"\n\1buildTypes {", text, count=1)
        else:
            inserted = 1
        text, signing_n = re.subn(
            r'(?m)^([ \t]*)signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            r'\1signingConfig = signingConfigs.getByName("release")', text, count=1)
    else:
        text, compile_n = re.subn(r"(?m)^([ \t]*)compileSdkVersion\s+[^\n]+", r"\g<1>compileSdkVersion 36", text, count=1)
        if not compile_n:
            text, compile_n = re.subn(r"(?m)^([ \t]*)compileSdk\s+[^\n]+", r"\g<1>compileSdk 36", text, count=1)
        text, target_n = re.subn(r"(?m)^([ \t]*)targetSdkVersion\s+[^\n]+", r"\g<1>targetSdkVersion 36", text, count=1)
        if not target_n:
            text, target_n = re.subn(r"(?m)^([ \t]*)targetSdk\s+[^\n]+", r"\g<1>targetSdk 36", text, count=1)
        text, min_n = re.subn(r"(?m)^([ \t]*)minSdkVersion\s+[^\n]+", r"\g<1>minSdkVersion 24", text, count=1)
        if not min_n:
            text, min_n = re.subn(r"(?m)^([ \t]*)minSdk\s+[^\n]+", r"\g<1>minSdk 24", text, count=1)
        block = '''
    signingConfigs {
        release {
            storeFile file(System.getenv("ANDROID_KEYSTORE_PATH"))
            storePassword System.getenv("ANDROID_STORE_PASSWORD")
            keyAlias System.getenv("ANDROID_KEY_ALIAS")
            keyPassword System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
'''
        if "signingConfigs {" not in text:
            text, inserted = re.subn(r"(?m)^([ \t]*)buildTypes\s*\{", block + r"\n\1buildTypes {", text, count=1)
        else:
            inserted = 1
        text, signing_n = re.subn(
            r"(?m)^([ \t]*)signingConfig\s+signingConfigs\.debug",
            r"\1signingConfig signingConfigs.release", text, count=1)

    if (compile_n != 1 or target_n != 1 or min_n != 1 or inserted != 1 or signing_n != 1):
        print(f"Unexpected Gradle layout: compile={compile_n}, target={target_n}, min={min_n}, inserted={inserted}, signing={signing_n}.", file=sys.stderr)
        return 1
    gradle.write_text(text, encoding="utf-8")
    print(f"Configured {gradle}: compileSdk=36, targetSdk=36, minSdk=24, OkHttp dependency, release signing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
