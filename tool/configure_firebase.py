#!/usr/bin/env python3
"""Install Firebase Android config from a GitHub Actions secret and wire Gradle."""
from pathlib import Path
import json
import os
import sys

EXPECTED_PACKAGE = "com.homagram.homagram"
PLUGIN_VERSION = "4.6.0"


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def main() -> int:
    raw = os.environ.get("GOOGLE_SERVICES_JSON", "").strip()
    if not raw:
        if os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
            print("Firebase config is unavailable to pull-request builds; skipping native Firebase wiring.")
            return 0
        return fail("Missing GitHub Actions secret: GOOGLE_SERVICES_JSON")

    try:
        config = json.loads(raw)
    except json.JSONDecodeError as error:
        return fail(f"GOOGLE_SERVICES_JSON is not valid JSON: {error}")

    clients = config.get("client", [])
    packages = [
        item.get("client_info", {}).get("android_client_info", {}).get("package_name")
        for item in clients
    ]
    if EXPECTED_PACKAGE not in packages:
        return fail(f"Firebase config does not contain Android package {EXPECTED_PACKAGE}.")

    settings = Path("android/settings.gradle.kts")
    app_gradle = Path("android/app/build.gradle.kts")
    if not settings.exists() or not app_gradle.exists():
        return fail("Expected Flutter-generated Kotlin Gradle files were not found.")

    settings_text = settings.read_text(encoding="utf-8")
    if "com.google.gms.google-services" not in settings_text:
        marker = "plugins {"
        if marker not in settings_text:
            return fail("Could not find plugins block in android/settings.gradle.kts.")
        settings_text = settings_text.replace(
            marker,
            marker + f'\n    id("com.google.gms.google-services") version "{PLUGIN_VERSION}" apply false',
            1,
        )
        settings.write_text(settings_text, encoding="utf-8")

    app_text = app_gradle.read_text(encoding="utf-8")
    if "com.google.gms.google-services" not in app_text:
        marker = "plugins {"
        if marker not in app_text:
            return fail("Could not find plugins block in android/app/build.gradle.kts.")
        app_text = app_text.replace(
            marker,
            marker + '\n    id("com.google.gms.google-services")',
            1,
        )
        app_gradle.write_text(app_text, encoding="utf-8")

    destination = Path("android/app/google-services.json")
    destination.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Configured Firebase for {EXPECTED_PACKAGE}; JSON remains ignored and is not committed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
