import tempfile
import unittest
from pathlib import Path

from build_index import build_db, validate_release_rows


def row(identifier: str, source: str, lat: float, lon: float) -> dict:
    return {
        "id": identifier,
        "source": source,
        "title": identifier,
        "description": "",
        "date_text": "1900",
        "date_year": 1900,
        "lat": lat,
        "lon": lon,
        "heading": None,
        "heading_confidence": "low",
        "thumbnail_url": f"https://example.com/{identifier}.jpg",
        "full_res_url": "",
        "attribution": "Test archive",
        "rights_uri": "https://example.com/rights",
    }


class PipelineSafetyTests(unittest.TestCase):
    def valid_rows(self) -> list[dict]:
        return [
            row("nyc", "oldnyc", 40.75, -73.98),
            row("sf", "wikimedia", 37.77, -122.42),
            row("chicago", "wikimedia", 41.88, -87.63),
        ]

    def test_release_validation_accepts_complete_https_inputs(self) -> None:
        validate_release_rows(self.valid_rows())

    def test_release_validation_rejects_single_source(self) -> None:
        rows = self.valid_rows()
        for item in rows:
            item["source"] = "oldnyc"
        with self.assertRaisesRegex(RuntimeError, "at least 2 independent sources"):
            validate_release_rows(rows)

    def test_release_validation_rejects_missing_city(self) -> None:
        rows = [item for item in self.valid_rows() if item["id"] != "chicago"]
        with self.assertRaisesRegex(RuntimeError, "Missing required release cities"):
            validate_release_rows(rows)

    def test_release_validation_rejects_insecure_thumbnail(self) -> None:
        rows = self.valid_rows()
        rows[0]["thumbnail_url"] = "http://example.com/photo.jpg"
        with self.assertRaisesRegex(RuntimeError, "without HTTPS thumbnails"):
            validate_release_rows(rows)

    def test_database_builder_runs_integrity_check(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "photos.db"
            build_db(self.valid_rows(), path)
            self.assertTrue(path.is_file())


if __name__ == "__main__":
    unittest.main()
