#!/usr/bin/env python3
"""Configure HomaGram Android permissions and auth callback."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest = Path("android/app/src/main/AndroidManifest.xml")
android_ns = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", android_ns)
android = f"{{{android_ns}}}"

def main() -> int:
    if not manifest.exists():
        print(f"Android manifest not found: {manifest}", file=sys.stderr)
        return 1
    tree = ET.parse(manifest)
    root = tree.getroot()
    required_permissions = (
        "android.permission.INTERNET",
        "android.permission.POST_NOTIFICATIONS",
    )
    for permission_name in required_permissions:
        if not any(item.get(android + "name") == permission_name
                   for item in root.findall("uses-permission")):
            permission = ET.Element("uses-permission")
            permission.set(android + "name", permission_name)
            root.insert(0, permission)
    activity = next((item for item in root.iter("activity")
                     if item.get(android + "name", "").endswith("MainActivity")), None)
    if activity is None:
        print("MainActivity not found in AndroidManifest.xml", file=sys.stderr)
        return 1
    configured = any(
        data.get(android + "scheme") == "homagram"
        for intent in activity.findall("intent-filter")
        for data in intent.findall("data")
    )
    if not configured:
        intent = ET.SubElement(activity, "intent-filter")
        ET.SubElement(intent, "action").set(android + "name", "android.intent.action.VIEW")
        ET.SubElement(intent, "category").set(android + "name", "android.intent.category.DEFAULT")
        ET.SubElement(intent, "category").set(android + "name", "android.intent.category.BROWSABLE")
        ET.SubElement(intent, "data").set(android + "scheme", "homagram")
    application = root.find("application")
    if application is None:
        print("application element not found in AndroidManifest.xml", file=sys.stderr)
        return 1
    cropper_name = "com.yalantis.ucrop.UCropActivity"
    if not any(item.get(android + "name") == cropper_name for item in application.findall("activity")):
        cropper = ET.SubElement(application, "activity")
        cropper.set(android + "name", cropper_name)
        cropper.set(android + "screenOrientation", "portrait")
        cropper.set(android + "theme", "@style/Theme.AppCompat.Light.NoActionBar")
    tree.write(manifest, encoding="utf-8", xml_declaration=True)
    print(f"Configured {manifest}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
