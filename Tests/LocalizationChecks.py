"""Exercise the localization gate with deliberately broken translation fixtures."""
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('localization_gate', ROOT / 'tools/check-localizations.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class LocalizationGateChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.resources = Path(self.temp.name) / 'Resources'
        shutil.copytree(gate.RESOURCES, self.resources)
        self.chinese = self.resources / 'zh-Hans.lproj/Localizable.strings'

    def check_gate(self):
        with contextlib.redirect_stdout(io.StringIO()):
            gate.validate(resource_root=self.resources)

    def test_missing_translation_is_rejected(self):
        self.chinese.write_text(self.chinese.read_text().replace('"app.version" = "版本 %@";\n', ''))
        with self.assertRaisesRegex(ValueError, 'missing='):
            self.check_gate()

    def test_wrong_format_type_is_rejected(self):
        self.chinese.write_text(self.chinese.read_text().replace('版本 %@', '版本 %d'))
        with self.assertRaisesRegex(ValueError, 'placeholder mismatch'):
            self.check_gate()

    def test_duplicate_key_is_rejected(self):
        self.chinese.write_text(self.chinese.read_text() + '"app.version" = "重复 %@";\n')
        with self.assertRaisesRegex(ValueError, 'duplicate keys'):
            self.check_gate()

    def test_positional_reordering_and_literal_percent(self):
        self.assertEqual(gate.placeholders('%@ %d 100%%'), gate.placeholders('%2$d %1$@ 100%%'))
        with self.assertRaises(ValueError):
            gate.placeholders('Broken %Q')


if __name__ == '__main__':
    unittest.main()
