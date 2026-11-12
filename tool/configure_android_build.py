#!/usr/bin/env python3
"""Set HomaGram Android API level and stable release signing."""
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

    # uCrop 2.2.11 references OkHttp directly for URI downloads; R8
    # requires these classes to be present in the release runtime.
    if kotlin:
        dependency = '    implementation("com.squareup.okhttp3:okhttp:4.12.0")'
        if "com.squareup.okhttp3:okhttp" not in text:
            text, dependency_n = re.subn(
                r"(?m)^dependencies\\s*\\{",
                lambda match: match.group(0) + "\\n" + dependency,
                text, count=1)
        else:
            dependency_n = 1
    else:
        dependency = "    implementation 'com.squareup.okhttp3:okhttp:4.12.0'"
        if "com.squareup.okhttp3:okhttp" not in text:
            text, dependency_n = re.subn(
                r"(?m)^dependencies\\s*\\{",
                lambda match: match.group(0) + "\\n" + dependency,
                text, count=1)
        else:
            dependency_n = 1
    if dependency_n != 1:
        print("Could not add the required OkHttp dependency.", file=sys.stderr)
        return 1
    if kotlin:
        text, compile_n = re.subn(r"(?m)^([ \t]*)compileSdk\s*=\s*[^\n]+", r"\g<1>compileSdk = 36", text, count=1)
        text, target_n = re.subn(r"(?m)^([ \t]*)targetSdk\s*=\s*[^\n]+", r"\g<1>targetSdk = 36", text, count=1)
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

    if (compile_n != 1 or target_n != 1 or inserted != 1 or signing_n != 1):
        print(f"Unexpected Gradle layout: compile={compile_n}, target={target_n}, inserted={inserted}, signing={signing_n}.", file=sys.stderr)
        return 1
    gradle.write_text(text, encoding="utf-8")
    print(f"Configured {gradle}: compileSdk=36, targetSdk=36, OkHttp dependency, release signing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
