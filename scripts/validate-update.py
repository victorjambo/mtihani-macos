#!/usr/bin/env python3
"""Validate release metadata; all cryptographic operations belong to Sparkle/Apple."""

import argparse
import base64
import pathlib
import plistlib
import re
import urllib.parse
import xml.etree.ElementTree as ET

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def https_url(value):
    url = urllib.parse.urlsplit(value)
    require(url.scheme == "https" and url.hostname, "Release URLs must use HTTPS.")
    require(not url.username and not url.password, "Do not embed credentials in release URLs.")
    require(not url.fragment, "Release URLs must not include fragments.")
    return url


def encoded_bytes(value, count):
    try:
        return len(base64.b64decode(value, validate=True)) == count
    except (ValueError, TypeError):
        return False


def validate_app(app, previous_feed=None):
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    https_url(info.get("SUFeedURL", ""))
    require(encoded_bytes(info.get("SUPublicEDKey", ""), 32), "Configure a valid Sparkle public key before packaging.")
    require(info.get("SUVerifyUpdateBeforeExtraction") is True, "Archive verification must be enabled.")
    require(info.get("SUEnableInstallerLauncherService") is True, "Sandbox installer service must be enabled.")
    require(info.get("SUEnableAutomaticChecks") is True, "Automatic checks must default to on.")
    require(info.get("SUAutomaticallyUpdate") is False, "Automatic downloads must default to off.")
    require(info.get("SUScheduledCheckInterval") == 86400, "Scheduled checks must default to daily.")
    require(re.fullmatch(r"\d+(\.\d+){0,2}", info.get("CFBundleShortVersionString", "")), "Invalid marketing version.")
    build = info.get("CFBundleVersion", "")
    require(re.fullmatch(r"[1-9]\d*", build), "Use a positive integer build number for releases.")
    if previous_feed and previous_feed.exists():
        for item in ET.parse(previous_feed).iter("item"):
            enclosure = item.find("enclosure")
            previous = item.findtext(SPARKLE + "version")
            if previous is None and enclosure is not None:
                previous = enclosure.get(SPARKLE + "version")
            require(previous is not None and previous.isdecimal(), "Previous feed has an invalid build number.")
            require(int(build) > int(previous), "Build number must exceed every release in the previous appcast.")
    framework = app / "Contents/Frameworks/Sparkle.framework/Versions/B"
    for component in ("Sparkle", "Autoupdate", "Updater.app", "XPCServices/Installer.xpc"):
        require((framework / component).exists(), f"Missing Sparkle component: {component}")
    return info


def validate_feed(feed):
    items = list(ET.parse(feed).iter("item"))
    require(items, "Appcast contains no releases.")
    builds = set()
    for item in items:
        enclosure = item.find("enclosure")
        require(enclosure is not None, "Appcast item is missing its archive.")
        build = item.findtext(SPARKLE + "version") or enclosure.get(SPARKLE + "version", "")
        require(build.isdecimal() and int(build) > 0, "Appcast has an invalid build number.")
        require(build not in builds, "Appcast has duplicate build numbers.")
        builds.add(build)
        for archive in item.iter("enclosure"):
            url = https_url(archive.get("url", ""))
            require(encoded_bytes(archive.get(SPARKLE + "edSignature", ""), 64), "Archive has no valid EdDSA signature metadata.")
            name = pathlib.PurePosixPath(urllib.parse.unquote(url.path)).name
            local_file = feed.parent / name
            require(local_file.is_file(), f"Missing local release artifact: {name}")
            require(local_file.stat().st_size == int(archive.get("length", "-1")), f"Archive size mismatch: {name}")
        notes = item.findtext(SPARKLE + "releaseNotesLink")
        if notes:
            https_url(notes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("app", "feed", "url"))
    parser.add_argument("path")
    parser.add_argument("--previous-feed", type=pathlib.Path)
    args = parser.parse_args()
    try:
        if args.kind == "app":
            validate_app(pathlib.Path(args.path), args.previous_feed)
        elif args.kind == "feed":
            validate_feed(pathlib.Path(args.path))
        else:
            https_url(args.path)
    except (ValueError, OSError, ET.ParseError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Release validation failed: {error}\n")


if __name__ == "__main__":
    main()
