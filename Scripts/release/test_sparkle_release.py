#!/usr/bin/env python3
"""Tests for sparkle_release.py. Run with: python3 -I Scripts/release/test_sparkle_release.py"""

import base64
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sparkle_release as sr  # noqa: E402

# RFC 8032, section 7.1, tests 1 to 3. (OpenSSL won't sign test 1's empty message.)
RFC_SEED_1 = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
RFC_PUBLIC_1 = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
RFC_SIGNATURE_1 = bytes.fromhex(
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
)
RFC_SEED_3 = bytes.fromhex("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7")
RFC_SIGNATURE_3 = bytes.fromhex(
    "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"
)
RFC_SEED_2 = bytes.fromhex("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
RFC_PUBLIC_2 = bytes.fromhex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
RFC_SIGNATURE_2 = bytes.fromhex(
    "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
)


def sample_feed(build=7, url="https://example.com/App.zip"):
    return sr.make_feed("App", "1.2.0", build, url, 1234, "c2lnbmF0dXJl", "26.0",
                        "- First change\n- Second change", pub_date="Mon, 19 Oct 2026 12:00:00 GMT")


class SigningTests(unittest.TestCase):
    def test_public_keys_match_rfc_8032(self):
        self.assertEqual(sr.public_key(RFC_SEED_1), RFC_PUBLIC_1)
        self.assertEqual(sr.public_key(RFC_SEED_2), RFC_PUBLIC_2)

    def test_signatures_match_rfc_8032(self):
        self.assertEqual(sr.sign(RFC_SEED_2, bytes.fromhex("72")), RFC_SIGNATURE_2)
        self.assertEqual(sr.sign(RFC_SEED_3, bytes.fromhex("af82")), RFC_SIGNATURE_3)

    def test_signatures_match_an_independent_implementation(self):
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        except ImportError:
            self.skipTest("cryptography isn't installed")
        seed = os.urandom(32)
        data = os.urandom(100_000)
        key = Ed25519PrivateKey.from_private_bytes(seed)
        self.assertEqual(sr.sign(seed, data), key.sign(data))
        key.public_key().verify(sr.sign(seed, data), data)

    def test_signing_needs_some_data(self):
        with self.assertRaises(sr.ReleaseError):
            sr.sign(RFC_SEED_1, b"")

    def test_verify_accepts_only_the_signed_bytes(self):
        self.assertTrue(sr.verify(RFC_PUBLIC_2, bytes.fromhex("72"), RFC_SIGNATURE_2))
        self.assertFalse(sr.verify(RFC_PUBLIC_2, bytes.fromhex("73"), RFC_SIGNATURE_2))
        self.assertFalse(sr.verify(RFC_PUBLIC_1, bytes.fromhex("72"), RFC_SIGNATURE_2))

    def test_seed_from_env_rejects_bad_values(self):
        os.environ["TEST_SEED"] = base64.b64encode(RFC_SEED_1).decode()
        self.assertEqual(sr.seed_from_env("TEST_SEED"), RFC_SEED_1)
        for bad in ("", "not base64!", base64.b64encode(b"short").decode()):
            os.environ["TEST_SEED"] = bad
            with self.assertRaises(sr.ReleaseError):
                sr.seed_from_env("TEST_SEED")
        del os.environ["TEST_SEED"]

    def test_signing_errors_never_show_the_seed(self):
        secret = base64.b64encode(b"x" * 31).decode()
        os.environ["TEST_SEED"] = secret
        with self.assertRaises(sr.ReleaseError) as caught:
            sr.seed_from_env("TEST_SEED")
        self.assertNotIn(secret, str(caught.exception))
        del os.environ["TEST_SEED"]


class FeedTests(unittest.TestCase):
    def test_feed_lists_one_signed_update(self):
        feed = sample_feed()
        self.assertEqual(sr.feed_builds(feed), [7])
        text = feed.decode()
        self.assertIn('<enclosure url="https://example.com/App.zip" length="1234" type="application/octet-stream" sparkle:edSignature="c2lnbmF0dXJl"/>', text)
        self.assertIn("<sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>", text)
        self.assertIn("<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>", text)
        self.assertIn('<description sparkle:format="markdown"><![CDATA[- First change\n- Second change\n]]></description>', text)

    def test_feed_escapes_and_refuses_unsafe_values(self):
        feed = sr.make_feed("A&B", "1.0", 1, "https://example.com/a?b=1&c=2", 1, "s", "26.0", "Notes")
        self.assertIn('url="https://example.com/a?b=1&amp;c=2"', feed.decode())
        self.assertIn("<title>A&amp;B</title>", feed.decode())
        with self.assertRaises(sr.ReleaseError):
            sr.make_feed("A", "1.0", 1, "http://example.com/a.zip", 1, "s", "26.0", "Notes")
        with self.assertRaises(sr.ReleaseError):
            sr.make_feed("A", "1.0", "1.1", "https://example.com/a.zip", 1, "s", "26.0", "Notes")
        with self.assertRaises(sr.ReleaseError):
            sr.make_feed("A", "1.0", 1, "https://example.com/a.zip", 1, "s", "26.0", "bad ]]> notes")

    def test_signed_feed_matches_sparkles_format(self):
        content = sample_feed()
        signed = sr.sign_feed(RFC_SEED_1, content)
        signature = base64.b64encode(sr.sign(RFC_SEED_1, content)).decode()
        expected_block = f"<!-- sparkle-signatures:\nedSignature: {signature}\nlength: {len(content)}\n-->\n".encode()
        self.assertEqual(signed, content + expected_block)
        self.assertEqual(sr.extract_feed(signed), (content, signature, len(content)))
        self.assertTrue(sr.verify_feed(RFC_PUBLIC_1, signed))
        self.assertFalse(sr.verify_feed(RFC_PUBLIC_2, signed))
        self.assertEqual(sr.feed_builds(signed), [7])
        with self.assertRaises(sr.ReleaseError):
            sr.sign_feed(RFC_SEED_1, signed)

    def test_tampered_or_unsigned_feeds_fail(self):
        content = sample_feed()
        signed = sr.sign_feed(RFC_SEED_1, content)
        self.assertFalse(sr.verify_feed(RFC_PUBLIC_1, content))
        self.assertFalse(sr.verify_feed(RFC_PUBLIC_1, signed.replace(b"1.2.0", b"1.2.1")))
        self.assertFalse(sr.verify_feed(RFC_PUBLIC_1, signed.replace(b"<channel>", b"<channel> ")))

    def test_feed_never_goes_back_to_an_older_build(self):
        published = sr.sign_feed(RFC_SEED_1, sample_feed(build=7))
        sr.require_newer(8, published)
        sr.require_newer(1, None)
        for build in (7, 6):
            with self.assertRaises(sr.ReleaseError):
                sr.require_newer(build, published)

    def test_builds_must_be_whole_numbers(self):
        feed = sample_feed().replace(b"<sparkle:version>7</sparkle:version>", b"<sparkle:version>7a</sparkle:version>")
        with self.assertRaises(sr.ReleaseError):
            sr.feed_builds(feed)


class CommandLineTests(unittest.TestCase):
    def test_public_key_command_prints_only_the_public_key(self):
        os.environ["TEST_SEED"] = base64.b64encode(RFC_SEED_1).decode()
        import contextlib
        import io
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(sr.main(["public-key", "--seed-env", "TEST_SEED"]), 0)
        self.assertEqual(output.getvalue().strip(), base64.b64encode(RFC_PUBLIC_1).decode())
        self.assertNotIn(os.environ["TEST_SEED"], output.getvalue())
        del os.environ["TEST_SEED"]


if __name__ == "__main__":
    unittest.main(verbosity=2)
