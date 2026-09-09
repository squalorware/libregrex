#!/usr/bin/env python3
import argparse
import os
import tempfile

from collections.abc import Iterable
from pathlib import Path
from string import Template
from urllib.request import Request, urlopen

# Type alias for convenience
CodepointPair = tuple[int, int]

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent

# Allow setting own default values via environment variables
DEFAULT_UNICODE_VERSION = os.getenv("UTF_VERSION", "17.0.0")
DEFAULT_OUTPUT_PATH = os.getenv("OUT_PATH", ROOT_DIR / "src/unicode/data/ucd_tables.zon")
DEFAULT_CACHE_DIR = os.getenv("CACHE_DIR", ROOT_DIR / ".unicode-cache")
DEFAULT_TEMPLATE_PATH = os.getenv("TEMPLATE_PATH", ROOT_DIR / "tools/ucd_tables.tpl")

MAX_UNICODE = 0x10FFFF
SURROGATE_START = 0xD800
SURROGATE_END = 0xDFFF
UCD_FILENAMES = (
    "UnicodeData.txt",
    "PropList.txt",
    "CaseFolding.txt",
)


def ucd_url(version: str, filename: str) -> str:
    return f"https://www.unicode.org/Public/{version}/ucd/{filename}"


def fetch_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)

    req = Request(url, headers={"User-Agent": "regrex-ucd-downloader/1.0"})
    temp_path: Path | None = None

    try:
        with urlopen(req, timeout=60) as res:
            status = res.getcode()

            if status != 200:
                raise RuntimeError(f"Failed to download {url}: HTTP {status}")

            with tempfile.NamedTemporaryFile(
                mode="wb",
                dir=dest.parent,
                prefix=f".{dest.name}.",
                suffix=".tmp",
                delete=False
            ) as temp:
                temp_path = Path(temp.name)

                while chunk := res.read(128 * 1024):
                    temp.write(chunk)

        os.replace(temp_path, dest)
        temp_path = None
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


def download_ucd_files(version: str, cache_dir: Path, force: bool) -> dict[str, Path]:
    """
    Downloads the files required to build a lookup table from the Unicode website

    If files are present at the output path, doesn't download unless force download flag is set to true

    Returns a map of filenames to their full paths (downloaded or cached)
    """
    cached_version_dir = cache_dir / version
    file_map: dict[str, Path] = {}

    for fname in UCD_FILENAMES:
        dest = cached_version_dir / fname

        if force or not dest.is_file():
            url = ucd_url(version, fname)

            print(f"Downloading {url}...")
            fetch_file(url, dest)
        else:
            print(f"Using cached {dest}")

        if dest.stat().st_size == 0:
            raise RuntimeError(f"File is empty: {dest}")

        file_map[fname] = dest

    return file_map


def is_valid_scalar(codepoint: int) -> bool:
    return (
        0 <= codepoint <= MAX_UNICODE
        and not SURROGATE_START
        <= codepoint
        <= SURROGATE_END
    )


def validate_pair(start: int,end: int) -> None:
    if start > end:
        raise ValueError(f"Invalid code-point range: U+{start:04X}..U+{end:04X}")

    if start < 0 or end > MAX_UNICODE:
        raise ValueError(f"Code-point range outside Unicode: U+{start:04X}..U+{end:04X}")

    overlaps_surrogates = (
        start <= SURROGATE_END
        and end >= SURROGATE_START
    )

    if overlaps_surrogates:
        raise ValueError(f"Codepoint range includes UTF-16 surrogates: U+{start:04X}..U+{end:04X}")


def merge_pairs(pairs: Iterable[CodepointPair]) -> list[CodepointPair]:
    ordered = sorted(pairs)

    if not ordered:
        return []

    merged: list[CodepointPair] = []

    current_start, current_end = ordered[0]

    for start, end in ordered[1:]:
        if start <= current_end + 1:
            current_end = max(current_end, end)
            continue

        merged.append((current_start, current_end))

        current_start = start
        current_end = end

    merged.append((current_start, current_end))

    return merged


def parse_unicode_data(path: Path) -> tuple[
    list[CodepointPair],
    list[CodepointPair],
]:
    """
    Parse UnicodeData.txt.

    Returns:
        digit_ranges:
            General_Category=Nd.

        word_ranges:
            General categories beginning with L or N, plus underscore.
    """

    d_ranges: list[CodepointPair] = []

    # Explicitly include LOW LINE, U+005F.
    w_ranges: list[CodepointPair] = [(0x005F, 0x005F)]

    # UnicodeData.txt sometimes represents large blocks using:
    #
    #   <..., First>
    #   <..., Last>
    pending_range: tuple[int, str, str] | None = None

    def add_category_range(rstart: int, rend: int, cat: str) -> None:
        if cat == "Nd":
            d_ranges.append((rstart, rend))

        if cat.startswith(("L", "N")):
            w_ranges.append((rstart, rend))

    with path.open("r", encoding="utf-8") as src:
        for ln, raw_line in enumerate(src, start=1):
            line = raw_line.rstrip("\r\n")

            if not line:
                continue

            fields = line.split(";")

            if len(fields) != 15:
                raise ValueError(f"{path}:{ln}: expected 15 fields, got {len(fields)}")

            codepoint = int(fields[0], 16)
            name = fields[1]
            category = fields[2]

            if name.endswith(", First>"):
                if pending_range is not None:
                    raise ValueError(f"{path}:{ln}: nested First range record")

                pending_range = (codepoint, name, category)
                continue

            if name.endswith(", Last>"):
                if pending_range is None:
                    raise ValueError(f"{path}:{ln}: Last record without First record")

                start, first_name, first_category = pending_range

                expected_last_name = first_name.replace(
                    ", First>",
                    ", Last>",
                )

                if name != expected_last_name or category != first_category:
                    raise ValueError(f"{path}:{ln}: mismatched First/Last records")

                add_category_range(start, codepoint, category)

                pending_range = None
                continue

            if pending_range is not None:
                raise ValueError(f"{path}:{ln}: missing Last record for {pending_range[1]}")

            if not is_valid_scalar(codepoint):
                # UnicodeData.txt contains surrogate records.
                # They cannot be represented as Unicode scalar values.
                continue

            add_category_range(codepoint, codepoint, category)

    if pending_range is not None:
        raise ValueError(f"{path}: unterminated First/Last range")

    return (
        merge_pairs(d_ranges),
        merge_pairs(w_ranges),
    )


def parse_codepoint_range(
    value: str,
) -> CodepointPair:
    value = value.strip()

    if ".." in value:
        start_text, end_text = value.split("..", maxsplit=1)

        start = int(start_text, 16)
        end = int(end_text, 16)
    else:
        start = int(value, 16)
        end = start

    validate_pair(start, end)

    return start, end


def parse_property_ranges(path: Path, property_name: str) -> list[CodepointPair]:
    ranges: list[CodepointPair] = []

    with path.open("r", encoding="utf-8") as src:
        for line_number, raw_line in enumerate(src, start=1):
            cont = raw_line.split("#", maxsplit=1)[0].strip()

            if not cont:
                continue

            parts = cont.split(";", maxsplit=1)

            if len(parts) != 2:
                raise ValueError(f"{path}:{line_number}: malformed property record")

            range_text = parts[0].strip()
            current_property = parts[1].strip()

            if current_property != property_name:
                continue

            ranges.append(parse_codepoint_range(range_text))

    if not ranges:
        raise ValueError(f"{path}: property {property_name!r} was not found")

    return merge_pairs(ranges)


def parse_simple_case_folding(path: Path) -> list[CodepointPair]:
    """
    Parse one-code-point Unicode case folding.

    Included statuses:
        C - common mapping
        S - simple mapping

    Ignored statuses:
        F - full, potentially multi-code-point mapping
        T - Turkic-specific mapping
    """

    mappings: dict[int, int] = {}

    with path.open("r", encoding="utf-8") as src:
        for ln, raw_line in enumerate(src, start=1):
            cont = raw_line.split("#", maxsplit=1)[0].strip()

            if not cont:
                continue

            fields = [field.strip() for field in cont.split(";")]

            if len(fields) < 3:
                raise ValueError(f"{path}:{ln}: malformed case-fold record")

            source_codepoint = int(fields[0], 16)
            status = fields[1]

            if status not in {"C", "S"}:
                continue

            mapping_values = fields[2].split()

            if len(mapping_values) != 1:
                raise ValueError(f"{path}:{ln}: simple case fold is not one-to-one")

            target_codepoint = int(mapping_values[0], 16)

            if not is_valid_scalar(source_codepoint):
                raise ValueError(f"{path}:{ln}: invalid source Unicode scalar")

            if not is_valid_scalar(target_codepoint):
                raise ValueError(f"{path}:{ln}: invalid target Unicode scalar")

            previous = mappings.get(source_codepoint)

            if (
                previous is not None
                and previous != target_codepoint
            ):
                raise ValueError(
                    f"{path}:{ln}: conflicting simple case folds for qU+{source_codepoint:04X}"
                )

            mappings[source_codepoint] = (
                target_codepoint
            )

    return sorted(mappings.items())


def zig_hex(codepoint: int) -> str:
    return f"0x{codepoint:06X}"


def render_pairs_list(pairs: list[CodepointPair]) -> str:
    lines = []

    for start, end in pairs:
        lines.append(
            "    .{ "
            f".start = {zig_hex(start)}, "
            f".end = {zig_hex(end)} "
            "},"
        )

    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=(
        "Download a pinned Unicode Character Database release and create a lookup table"
    ))
    parser.add_argument(
        "-v", "--unicode-version",
        default=DEFAULT_UNICODE_VERSION,
        help=f"Unicode Character Database version (default: {DEFAULT_UNICODE_VERSION})",
    )

    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=DEFAULT_OUTPUT_PATH,
        help=f"Path to write the output .zon file to (default: {DEFAULT_OUTPUT_PATH})",
    )

    parser.add_argument(
        "-c", "--cache-dir",
        type=Path,
        default=DEFAULT_CACHE_DIR,
        help=f"Path to store the downloaded UCD files (default: {DEFAULT_CACHE_DIR})",
    )

    parser.add_argument(
        "-f", "--force-download",
        action="store_true",
        help="Redownload UCD files even when cached files exist.",
    )

    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    files = download_ucd_files(
        version=args.unicode_version,
        cache_dir=args.cache_dir,
        force=args.force_download,
    )

    digit_ranges, word_ranges = parse_unicode_data(files["UnicodeData.txt"])
    whitespace_ranges = parse_property_ranges(files["PropList.txt"], "White_Space")
    case_folds = parse_simple_case_folding(files["CaseFolding.txt"])

    with open(DEFAULT_TEMPLATE_PATH, "r") as f:
        content = f.read()

    template = Template(content)
    output = template.substitute({
        "version": args.unicode_version,
        "digit_ranges": render_pairs_list(digit_ranges),
        "word_ranges": render_pairs_list(word_ranges),
        "whitespace_ranges": render_pairs_list(whitespace_ranges),
        "case_folds": render_pairs_list(case_folds),
    })

    with args.output.open("wb") as f:
        f.write(output.encode("utf-8"))

    print(f"Generated {args.output}")
    print(f"  Unicode version: {args.unicode_version}")
    print(f"  digit ranges: {len(digit_ranges)}")
    print(f"  word ranges: {len(word_ranges)}")
    print(f"  whitespace ranges: {len(whitespace_ranges)}")
    print(f"  simple case folds: {len(case_folds)}")
