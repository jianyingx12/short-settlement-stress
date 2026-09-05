from __future__ import annotations

import io
import json
import tempfile
import unittest
import zipfile
from datetime import date
from pathlib import Path

from src.ingestion.common import AcquisitionError, ValidationResult, download_validated
from src.ingestion.finra_short_interest import parse_partitions, validate_short_interest
from src.ingestion.finra_short_volume import parse_archive_page, validate_short_volume
from src.ingestion.sec_ftd import parse_source_links, validate_ftd_zip


SHORT_INTEREST_HEADER = (
    "accountingYearMonthNumber|symbolCode|issueName|issuerServicesGroupExchangeCode|"
    "marketClassCode|currentShortPositionQuantity|previousShortPositionQuantity|"
    "stockSplitFlag|averageDailyVolumeQuantity|daysToCoverQuantity|revisionFlag|"
    "changePercent|changePreviousNumber|settlementDate\n"
)


class CommonAcquisitionTests(unittest.TestCase):
    def test_existing_valid_file_is_reused_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.txt"
            path.write_bytes(b"valid")

            def validator(content: bytes) -> ValidationResult:
                self.assertEqual(content, b"valid")
                return ValidationResult(1, "2018-08-01", "2018-08-01", ("field",))

            record = download_validated(
                "https://invalid.example/should-not-be-called", path, validator
            )
            self.assertEqual(record["status"], "existing")


class ShortVolumeTests(unittest.TestCase):
    def test_validates_decimal_quantities_and_trailer(self) -> None:
        content = (
            "Date|Symbol|ShortVolume|ShortExemptVolume|TotalVolume|Market\n"
            "20260904|A|10.5|1|30.25|Q,N\n"
            "1\n"
        ).encode()
        result = validate_short_volume(content, date(2026, 9, 4))
        self.assertEqual(result.row_count, 1)

    def test_rejects_html(self) -> None:
        with self.assertRaises(AcquisitionError):
            validate_short_volume(b"<!doctype html><title>Error</title>")

    def test_parses_archive_year_values_and_links(self) -> None:
        html = """
        <select name="custom_year[year]"><option value="8">2018</option></select>
        <a href="https://cdn.finra.org/equity/regsho/daily/CNMSshvol20180801.txt">file</a>
        """
        years, links = parse_archive_page(html)
        self.assertEqual(years, {2018: "8"})
        self.assertEqual(len(links), 1)


class ShortInterestTests(unittest.TestCase):
    def test_validates_observed_pipe_delimited_schema(self) -> None:
        row = "20180815|A|Agilent|A|NYSE|10|9||100|1.00||11.11|1|2018-08-15\n"
        result = validate_short_interest(
            (SHORT_INTEREST_HEADER + row).encode(), date(2018, 8, 15)
        )
        self.assertEqual(result.row_count, 1)

    def test_rejects_missing_columns(self) -> None:
        with self.assertRaises(AcquisitionError):
            validate_short_interest(b"settlementDate|symbolCode\n2018-08-15|A\n")

    def test_parses_partitions(self) -> None:
        payload = json.dumps(
            {"availablePartitions": [{"partitions": ["2018-08-15"]}]}
        )
        self.assertEqual(parse_partitions(payload), [date(2018, 8, 15)])


class SecFtdTests(unittest.TestCase):
    def test_validates_zip_and_missing_price_marker(self) -> None:
        raw = (
            "SETTLEMENT DATE|CUSIP|SYMBOL|QUANTITY (FAILS)|DESCRIPTION|PRICE\n"
            "20180801|000000001|ABC|100|ABC CORP|.\n"
        ).encode()
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("cnsfails201808a.txt", raw)
        result = validate_ftd_zip(buffer.getvalue())
        self.assertEqual(result.row_count, 1)

    def test_accepts_historical_windows_1252_descriptions(self) -> None:
        raw = (
            "SETTLEMENT DATE|CUSIP|SYMBOL|QUANTITY (FAILS)|DESCRIPTION|PRICE\n"
            "20180801|000000001|ABC|100|ABC CORP \u00bb|1.25\n"
        ).encode("cp1252")
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("cnsfails201808a.txt", raw)
        result = validate_ftd_zip(buffer.getvalue())
        self.assertEqual(result.row_count, 1)
        self.assertEqual(
            result.anomalies,
            ("cnsfails201808a.txt decoded as Windows-1252",),
        )

    def test_validates_historical_trailer_count(self) -> None:
        raw = (
            "SETTLEMENT DATE|CUSIP|SYMBOL|QUANTITY (FAILS)|DESCRIPTION|PRICE\n"
            "20180801|000000001|ABC|100|ABC CORP|1.25\n"
            "Trailer record count 1|||||\n"
            "Trailer total quantity of shares 100|||||\n"
        ).encode()
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("cnsfails201808a.txt", raw)
        result = validate_ftd_zip(buffer.getvalue())
        self.assertEqual(result.row_count, 1)
        self.assertIn(
            "cnsfails201808a.txt contains validated record count, total quantity trailers",
            result.anomalies,
        )

    def test_preserves_and_counts_blank_symbols(self) -> None:
        raw = (
            "SETTLEMENT DATE|CUSIP|SYMBOL|QUANTITY (FAILS)|DESCRIPTION|PRICE\n"
            "20181001|000000001||100|UNKNOWN ISSUE|1.25\n"
        ).encode()
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("cnsfails201810a.txt", raw)
        result = validate_ftd_zip(buffer.getvalue())
        self.assertEqual(result.row_count, 1)
        self.assertIn("1 rows have blank symbol", result.anomalies)

    def test_rejects_non_zip(self) -> None:
        with self.assertRaises(AcquisitionError):
            validate_ftd_zip(b"not a zip")

    def test_discovers_only_ftd_zip_links(self) -> None:
        html = """
        <a href="/files/data/fails-deliver-data/cnsfails201808a.zip">FTD</a>
        <a href="/other.zip">Other</a>
        """
        links = parse_source_links(html)
        self.assertEqual(
            links,
            ["https://www.sec.gov/files/data/fails-deliver-data/cnsfails201808a.zip"],
        )


if __name__ == "__main__":
    unittest.main()
