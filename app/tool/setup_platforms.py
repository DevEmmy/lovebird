#!/usr/bin/env python3
"""
Generates the native Android/iOS/web folders with `flutter create` and adds the
permissions + deep link Lovebird needs. Safe to re-run.

    cd app && python3 tool/setup_platforms.py
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEME = "io.lovebird.app"


def run(cmd):
    print("$", " ".join(cmd))
    subprocess.run(cmd, cwd=ROOT, check=True)


def patch_android():
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not manifest.exists():
        return
    s = manifest.read_text()
    perms = [
        "android.permission.INTERNET",
        "android.permission.RECORD_AUDIO",
        "android.permission.CAMERA",
        "android.permission.MODIFY_AUDIO_SETTINGS",
        "android.permission.BLUETOOTH",
        "android.permission.BLUETOOTH_CONNECT",
        "android.permission.ACCESS_NETWORK_STATE",
    ]
    for p in perms:
        if p not in s:
            s = s.replace("<application", f'<uses-permission android:name="{p}"/>\n    <application', 1)
    if SCHEME not in s:
        deep_link = f"""
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="{SCHEME}" android:host="login-callback" />
            </intent-filter>"""
        s = re.sub(r"(</intent-filter>)", r"\1" + deep_link, s, count=1)
    manifest.write_text(s)

    gradle = ROOT / "android/app/build.gradle.kts"
    if not gradle.exists():
        gradle = ROOT / "android/app/build.gradle"
    if gradle.exists():
        g = gradle.read_text()
        # LiveKit/WebRTC and record need minSdk 21+; we use 23 for modern audio APIs.
        g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", g)
        g = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", g)
        gradle.write_text(g)
    print("✓ Android permissions, deep link, minSdk")


def patch_ios():
    plist = ROOT / "ios/Runner/Info.plist"
    if not plist.exists():
        return
    s = plist.read_text()
    entries = {
        "NSCameraUsageDescription": "Lovebird uses your camera for photos and video calls with your partner.",
        "NSMicrophoneUsageDescription": "Lovebird uses your microphone for voice notes and calls with your partner.",
        "NSPhotoLibraryUsageDescription": "Lovebird lets you share photos with your partner and save memories.",
    }
    add = ""
    for k, v in entries.items():
        if k not in s:
            add += f"\t<key>{k}</key>\n\t<string>{v}</string>\n"
    if SCHEME not in s:
        add += f"""\t<key>CFBundleURLTypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleURLSchemes</key>
\t\t\t<array><string>{SCHEME}</string></array>
\t\t</dict>
\t</array>
"""
    if "UIBackgroundModes" not in s:
        add += "\t<key>UIBackgroundModes</key>\n\t<array><string>audio</string><string>voip</string></array>\n"
    if add:
        s = s.replace("</dict>\n</plist>", add + "</dict>\n</plist>")
        plist.write_text(s)

    podfile = ROOT / "ios/Podfile"
    if podfile.exists():
        p = podfile.read_text()
        p = re.sub(r"#\s*platform :ios, '[\d.]+'", "platform :ios, '13.0'", p)
        podfile.write_text(p)
    print("✓ iOS usage descriptions, URL scheme, background audio, iOS 13")


def main():
    if not (ROOT / "android").exists() or not (ROOT / "ios").exists():
        run(["flutter", "create", "--org", "io.lovebird", "--project-name", "lovebird", "--platforms", "android,ios,web", "."])
    patch_android()
    patch_ios()
    print("Done. Next: flutter pub get && flutter run --dart-define-from-file=env.json")


if __name__ == "__main__":
    sys.exit(main())
