from __future__ import annotations

import tempfile
import unittest
import zipfile
from decimal import Decimal
from pathlib import Path

from src.loading.finra_short_volume import rows as short_volume_rows
from src.loading.sec_ftd import rows as ftd_rows


class ShortVolumeLoadingTests(unittest.TestCase):
    def test_keeps_fractional_values_and_excludes_trailer(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "CNMSshvol20260904.txt"
            path.write_text(
                "Date|Symbol|ShortVolume|ShortExemptVolume|TotalVolume|Market\n"
                "20260904|ABC|10.5|0.25|30.75|Q,N\n"
                "1\n",
                encoding="utf-8",
            )
            parsed = list(short_volume_rows(path))
        self.assertEqual(len(parsed), 1)
        self.assertEqual(parsed[0][2:5], (Decimal("10.5"), Decimal("0.25"), Decimal("30.75")))
        self.assertEqual(parsed[0][-1], 2)


class SecFtdLoadingTests(unittest.TestCase):
    def test_preserves_blank_symbol_and_unparseable_price(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cnsfails201808a.zip"
            content = (
                "SETTLEMENT DATE|CUSIP|SYMBOL|QUANTITY (FAILS)|DESCRIPTION|PRICE\n"
                "20180801|000000001||100|UNKNOWN ISSUE|not available\n"
                "Trailer record count 1|||||\n"
            )
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("cnsfails201808a.txt", content)
            parsed = list(ftd_rows(path))
        self.assertEqual(len(parsed), 1)
        self.assertIsNone(parsed[0][2])
        self.assertIsNone(parsed[0][5])
        self.assertEqual(parsed[0][6], "not available")
        self.assertEqual(parsed[0][-1], 2)


if __name__ == "__main__":
    unittest.main()
