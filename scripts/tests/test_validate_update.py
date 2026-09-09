"""Release guard tests use synthetic metadata, with no credentials or network."""

import base64
import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "validate_update", pathlib.Path(__file__).parents[1] / "validate-update.py"
)
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = pathlib.Path(self.temporary.name)
        self.app = self.directory / "Mtihani.app"
        self.info = {
            "SUFeedURL": "https://updates.example.test/appcast.xml",
            "SUPublicEDKey": base64.b64encode(bytes(32)).decode(),
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "42",
            "SUVerifyUpdateBeforeExtraction": True,
            "SUEnableInstallerLauncherService": True,
            "SUEnableAutomaticChecks": True,
            "SUAutomaticallyUpdate": False,
            "SUScheduledCheckInterval": 86400,
        }
        self.write_app()
        framework = self.app / "Contents/Frameworks/Sparkle.framework/Versions/B"
        for component in ("Sparkle", "Autoupdate", "Updater.app", "XPCServices/Installer.xpc"):
            path = framework / component
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()

    def write_app(self):
        path = self.app / "Contents/Info.plist"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(plistlib.dumps(self.info))

    def write_feed(self, build="41", signature=None, length="4", scheme="https"):
        if signature is None:
            signature = base64.b64encode(bytes(64)).decode()
        (self.directory / "Mtihani.dmg").write_bytes(b"test")
        feed = self.directory / "appcast.xml"
        feed.write_text(f"""<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel><item><sparkle:version>{build}</sparkle:version>
            <enclosure url="{scheme}://updates.example.test/Mtihani.dmg"
                length="{length}" sparkle:edSignature="{signature}" />
            </item></channel></rss>""")
        return feed

    def test_complete_metadata_passes(self):
        validator.validate_app(self.app, self.write_feed())
        validator.validate_feed(self.write_feed())

    def test_public_key_is_required(self):
        for key in ("", "$(SPARKLE_PUBLIC_ED_KEY)", "invalid"):
            self.info["SUPublicEDKey"] = key
            self.write_app()
            with self.assertRaisesRegex(ValueError, "public key"):
                validator.validate_app(self.app)

    def test_build_must_increase(self):
        for previous_build in ("42", "43"):
            with self.assertRaisesRegex(ValueError, "exceed"):
                validator.validate_app(self.app, self.write_feed(build=previous_build))

    def test_sparkle_installer_must_be_embedded(self):
        (self.app / "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc").unlink()
        with self.assertRaisesRegex(ValueError, "Missing Sparkle component"):
            validator.validate_app(self.app)

    def test_automatic_downloads_cannot_default_on(self):
        self.info["SUAutomaticallyUpdate"] = True
        self.write_app()
        with self.assertRaisesRegex(ValueError, "default to off"):
            validator.validate_app(self.app)

    def test_rejects_unsigned_or_changed_archive_metadata(self):
        with self.assertRaisesRegex(ValueError, "signature"):
            validator.validate_feed(self.write_feed(signature=""))
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            validator.validate_feed(self.write_feed(length="5"))

    def test_rejects_insecure_release_urls(self):
        for url in ("http://updates.example.test/", "file:///appcast.xml", "https://user:secret@example.test/"):
            with self.assertRaises(ValueError):
                validator.https_url(url)
        with self.assertRaisesRegex(ValueError, "HTTPS"):
            validator.validate_feed(self.write_feed(scheme="http"))


if __name__ == "__main__":
    unittest.main()
