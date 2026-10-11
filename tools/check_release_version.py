import argparse
from pathlib import Path
import re
import tomllib


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--ref", default="")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    with (root / "Cargo.toml").open("rb") as source:
        rust_version = tomllib.load(source)["package"]["version"]
    flutter_match = re.search(
        r"^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$",
        (root / "flutter/pubspec.yaml").read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if flutter_match is None:
        parser.error("flutter/pubspec.yaml must contain a stable version")
    versions = {
        "Cargo.toml": rust_version,
        "flutter/pubspec.yaml": flutter_match.group(1),
        "build.yml VERSION": args.version,
    }
    if args.ref.startswith("refs/tags/"):
        versions["release tag"] = args.ref.removeprefix("refs/tags/").removeprefix("v")
    if len(set(versions.values())) != 1:
        parser.error(f"Release versions must match: {versions}")
    print(f"Release versions match: {rust_version}")


if __name__ == "__main__":
    main()
