import importlib.util
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-sensitive.py").resolve()
spec = importlib.util.spec_from_file_location("upload_safety", SCRIPT)
safety = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safety)


def dummy_private_key(kind=b"RSA"):
    return b"-----BEGIN " + kind + b" PRIVATE KEY-----\nnot-a-real-key\n"


class UploadSafetyTests(unittest.TestCase):
    def test_private_file_extensions_and_names(self):
        for name in ["signing.p12", "SIGNING.PFX", "AuthKey_test.p8", "secret.key", "key.pem", "keys/id_ed25519", ".env", ".env.production"]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                safety.inspect(name, b"dummy")

    def test_renamed_pem_private_keys_are_rejected(self):
        for kind in [b"RSA", b"EC", b"OPENSSH", b"ENCRYPTED"]:
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                safety.inspect("innocent.txt", dummy_private_key(kind))
        with self.assertRaises(ValueError):
            safety.inspect("innocent.txt", b"-----BEGIN " + b"PRIVATE KEY-----")

    def test_public_certificate_and_credential_examples_allowed(self):
        safety.inspect("developer.cer", b"-----BEGIN CERTIFICATE-----\npublic\n")
        safety.inspect(".env.example", b"API_KEY=replace-me")
        safety.inspect("Sources/Volume.swift", b"let volume = 0")

    def test_zip_entries_are_inspected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "release.zip"
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("App.app/Contents/Resources/credentials.p12", b"dummy")
            with self.assertRaises(ValueError):
                safety.scan_artifact(archive)
            with zipfile.ZipFile(archive, "w") as bundle:
                bundle.writestr("App.app/Contents/Resources/readme.txt", dummy_private_key())
            with self.assertRaises(ValueError):
                safety.scan_artifact(archive)

    def test_nested_archives_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            inner = Path(directory) / "inner.zip"
            outer = Path(directory) / "outer.zip"
            with zipfile.ZipFile(inner, "w") as bundle:
                bundle.writestr("file.txt", "test")
            with zipfile.ZipFile(outer, "w") as bundle:
                bundle.write(inner, "data.bin")
            with self.assertRaises(ValueError):
                safety.scan_artifact(outer)

    def test_oversized_data_and_unexpected_symlinks_are_rejected(self):
        previous = safety.MAX_BYTES
        try:
            safety.MAX_BYTES = 4
            with self.assertRaises(ValueError):
                safety.inspect("file.txt", b"12345")
        finally:
            safety.MAX_BYTES = previous
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "source.txt").write_text("safe")
            (root / "link.txt").symlink_to(root / "source.txt")
            with self.assertRaises(ValueError):
                safety.scan_artifact(root)

    def test_staged_blob_is_checked_instead_of_working_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                subprocess.run(["git", *args], cwd=directory, check=True, capture_output=True)
            git("init", "-q")
            file = Path(directory) / "notes.txt"
            file.write_bytes(dummy_private_key())
            git("add", "notes.txt")
            file.write_text("safe working copy")
            result = subprocess.run(["python3", str(SCRIPT), "--staged"], cwd=directory, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(b"not-a-real-key", result.stderr)
            git("add", "notes.txt")
            file.write_bytes(dummy_private_key())
            result = subprocess.run(["python3", str(SCRIPT), "--staged"], cwd=directory, capture_output=True)
            self.assertEqual(result.returncode, 0)

    def test_deleted_historical_key_still_blocks_push(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                subprocess.run(["git", *args], cwd=directory, check=True, capture_output=True)
            git("init", "-q")
            git("config", "user.name", "Safety Test")
            git("config", "user.email", "test@example.invalid")
            file = Path(directory) / "secret.p12"
            file.write_bytes(b"synthetic signing container")
            git("add", ".")
            git("commit", "-qm", "dummy credential")
            git("rm", "secret.p12")
            git("commit", "-qm", "remove dummy")
            result = subprocess.run(["python3", str(SCRIPT), "--history"], cwd=directory, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"secret.p12", result.stderr)


if __name__ == "__main__":
    unittest.main()
