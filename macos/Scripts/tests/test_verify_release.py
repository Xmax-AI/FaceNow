import importlib.util
import json
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location("verify_release", Path(__file__).resolve().parents[1] / "verify-release.py")
verify_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify_release)


class DiagnosticJSONTests(unittest.TestCase):
    def test_reads_payload_with_startup_and_shutdown_logs(self):
        payload = {"hostProcessID": 1, "helperProcessID": 2, "pixelProcessingVerified": True}
        output = b"SDK starting\n" + json.dumps(payload).encode() + b"\nSDK shutdown complete\n"
        self.assertEqual(verify_release.diagnostic_json(output, payload.keys()), payload)

    def test_ignores_unrelated_json_after_the_diagnostic(self):
        output = b'{"hostProcessID":1,"helper":{}}\n{"log":"closing"}\n'
        self.assertEqual(verify_release.diagnostic_json(output, ["hostProcessID", "helper"]), {"hostProcessID": 1, "helper": {}})

    def test_retains_failed_checks_for_the_callers_validation(self):
        output = b'{"hostProcessID":1,"pixelProcessingVerified":false}\nSDK stopped\n'
        payload = verify_release.diagnostic_json(output, ["hostProcessID", "pixelProcessingVerified"])
        self.assertFalse(payload["pixelProcessingVerified"])

    def test_requires_the_expected_payload_fields(self):
        with self.assertRaises(AssertionError):
            verify_release.diagnostic_json(b'noise\n{"log":"closing"}\n', ["hostProcessID"])

    def test_tolerates_invalid_bytes_in_sdk_log_lines(self):
        output = b'\xff SDK startup\n{"hostProcessID":1}\n\xfe SDK shutdown\n'
        self.assertEqual(verify_release.diagnostic_json(output, ["hostProcessID"]), {"hostProcessID": 1})


if __name__ == "__main__":
    unittest.main()
