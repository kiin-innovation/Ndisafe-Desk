import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from xml.etree import ElementTree

import preprocess


class UpdatePackageTests(unittest.TestCase):
    def generated_variables(self, product):
        captured = []

        def generate(_file, _start, _end, callback):
            lines = []
            callback(lines, 0)
            captured.extend(lines)
            return True

        args = SimpleNamespace(app_name=product, manufacturer="Kiin innovation")
        with patch.object(preprocess, "app_name", product, create=True), patch.object(
            preprocess, "gen_content_between_tags", side_effect=generate
        ):
            self.assertTrue(preprocess.gen_pre_vars(args, "bundle"))
        return "".join(captured)

    def test_ndisafe_keeps_msi_upgrade_identity_and_runtime_config_name(self):
        variables = self.generated_variables("ndisafe-desk")
        self.assertIn('<?define Product="ndisafe-desk" ?>', variables)
        self.assertIn('<?define ConfigProduct="NDISafe Desk" ?>', variables)
        self.assertIn(str(uuid.uuid5(uuid.NAMESPACE_OID, "ndisafe-desk.exe")), variables)

    def test_upstream_config_name_is_unchanged(self):
        self.assertIn('<?define ConfigProduct="RustDesk" ?>', self.generated_variables("RustDesk"))

    def test_first_install_import_runs_before_service_start_and_preserves_explicit_source(self):
        root = ElementTree.parse(Path(__file__).parent / "Package/Components/RustDesk.wxs")
        ns = {"w": "http://wixtoolset.org/schemas/v4/wxs"}
        prop = root.find('.//w:Property[@Id="IMPORT_CONFIG"]', ns)
        self.assertEqual(prop.attrib["Secure"], "yes")
        default_source = root.find('.//w:Custom[@Action="ImportConfig.SetSource"]', ns)
        self.assertEqual(default_source.attrib["Before"], "ImportConfig")
        self.assertIn("NOT IMPORT_CONFIG AND NOT Installed AND NOT REMOVE", default_source.attrib["Condition"])
        self.assertIn('"$(var.Product)"="ndisafe-desk"', default_source.attrib["Condition"])
        action = root.find('.//w:CustomAction[@Id="ImportConfig"]', ns)
        self.assertEqual(action.attrib["Execute"], "deferred")
        self.assertEqual(action.attrib["Impersonate"], "no")
        self.assertEqual(action.attrib["Return"], "check")
        self.assertEqual(action.attrib["ExeCommand"], '--import-config "[IMPORT_CONFIG]" --for-install')
        schedule = root.find('.//w:Custom[@Action="ImportConfig"]', ns)
        self.assertEqual(schedule.attrib["After"], "InstallFiles")
        self.assertEqual(schedule.attrib["Condition"], "IMPORT_CONFIG AND NOT Installed AND NOT REMOVE")
        service = root.find('.//w:Custom[@Action="CreateStartService"]', ns)
        self.assertEqual(service.attrib["Before"], "InstallFinalize")
        stop_config = root.find('.//w:CustomAction[@Id="SetPropertyServiceStop.SetParam.ConfigFile"]', ns)
        self.assertIn("$(var.ConfigProduct)", stop_config.attrib["Value"])


if __name__ == "__main__":
    unittest.main()
