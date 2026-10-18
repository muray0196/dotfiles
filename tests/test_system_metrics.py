#!/usr/bin/env python3
"""Resolve exact AMD GPU names without guessing from a shared PCI device ID."""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]
                     / "modules/quickshell/.config/quickshell/performance/scripts"))

import system_metrics as metrics  # noqa: E402


class GpuModelTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.device = self.root / "device"
        self.device.mkdir()
        (self.device / "vendor").write_text("0x1002\n")
        (self.device / "device").write_text("0x7590\n")
        (self.device / "revision").write_text("0xc0\n")
        self.amdgpu_ids = self.root / "amdgpu.ids"
        self.amdgpu_ids.write_text(
            "# Device, revision, name\n1.0.0\n"
            "7590, C0, AMD Radeon RX 9060 XT\n"
            "7590, C1, AMD Radeon RX 9060 XT LP\n"
            "7590, C7, AMD Radeon RX 9060\n"
        )
        pci_ids = self.root / "pci.ids"
        pci_ids.write_text(
            "1002  AMD\n\t7590  Navi 44 [Radeon RX 9050 / 9060 XT]\n"
            "10de  NVIDIA\n\t7590  Other GPU\n"
        )
        paths = patch.multiple(metrics, AMDGPU_IDS=self.amdgpu_ids, PCI_IDS=pci_ids)
        paths.start()
        self.addCleanup(paths.stop)

    def test_revision_selects_exact_model_for_shared_device_id(self):
        for revision, name in (
            ("c0", "AMD Radeon RX 9060 XT"),
            ("c1", "AMD Radeon RX 9060 XT LP"),
            ("c7", "AMD Radeon RX 9060"),
        ):
            with self.subTest(revision=revision):
                (self.device / "revision").write_text("0x" + revision)
                self.assertEqual(metrics.read_pci_model(self.device), name)

    def test_unknown_revision_preserves_generic_pci_name(self):
        (self.device / "revision").write_text("0xff")
        self.assertEqual(metrics.read_pci_model(self.device), "Radeon RX 9050 / 9060 XT")

    def test_missing_revision_preserves_generic_pci_name(self):
        (self.device / "revision").unlink()
        self.assertEqual(metrics.read_pci_model(self.device), "Radeon RX 9050 / 9060 XT")

    def test_missing_libdrm_database_preserves_generic_pci_name(self):
        self.amdgpu_ids.unlink()
        self.assertEqual(metrics.read_pci_model(self.device), "Radeon RX 9050 / 9060 XT")

    def test_non_amd_vendor_does_not_use_amd_database(self):
        (self.device / "vendor").write_text("0x10de")
        self.assertEqual(metrics.read_pci_model(self.device), "Other GPU")

    def test_invalid_database_rows_do_not_hide_valid_names(self):
        self.amdgpu_ids.write_text("invalid, row, skip\n7590, C0, AMD Radeon RX 9060 XT\n")
        self.assertEqual(metrics.read_pci_model(self.device), "AMD Radeon RX 9060 XT")


if __name__ == "__main__":
    unittest.main()
