import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from device_identities import IDENTITIES, identity, source_digest, uninstall_script


class DeviceIdentityTests(unittest.TestCase):
    def test_editions_have_no_shared_system_identity(self):
        domestic, oversea = identity('domestic'), identity('oversea')
        for key in domestic:
            self.assertNotEqual(domestic[key], oversea[key], key)
        self.assertNotEqual(source_digest('domestic'), source_digest('oversea'))

    def test_uninstaller_targets_only_its_own_driver(self):
        for edition, selected in IDENTITIES.items():
            script = uninstall_script(edition)
            self.assertIn("driver='/Library/Audio/Plug-Ins/HAL/" + selected['driverFilename'] + "'", script)
            self.assertIn("[ \"$identifier\" = '" + selected['driverBundleID'] + "' ] || exit 1", script)
            for other, other_identity in IDENTITIES.items():
                if other != edition:
                    self.assertNotIn(other_identity['driverFilename'], script)
                    self.assertNotIn(other_identity['driverBundleID'], script)
            self.assertNotIn('killall', script)
            self.assertNotIn('launchctl', script)

    def test_unknown_edition_cannot_build_domestic_driver_by_accident(self):
        with self.assertRaises(ValueError):
            identity('overseas')
