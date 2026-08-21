#!/usr/bin/env python3
"""Enforce TST-001 line coverage for the linguistic front end."""

from __future__ import annotations

import json
import pathlib
import sys


FRONTEND_PATH_COMPONENTS = ("Sources", "Choir", "LinguisticFrontend")


def is_linguistic_frontend_source(filename: str) -> bool:
    """Match the front-end directory in absolute, relative, or Windows paths."""
    parts = pathlib.PurePosixPath(filename.replace("\\", "/")).parts
    component_count = len(FRONTEND_PATH_COMPONENTS)
    return any(
        parts[index : index + component_count] == FRONTEND_PATH_COMPONENTS
        for index in range(len(parts) - component_count + 1)
    )


def main() -> int:
    if len(sys.argv) not in {2, 3}:
        print("usage: check_frontend_coverage.py COVERAGE_JSON [MINIMUM_PERCENT]", file=sys.stderr)
        return 2

    report_path = pathlib.Path(sys.argv[1])
    minimum = float(sys.argv[2]) if len(sys.argv) == 3 else 85.0
    report = json.loads(report_path.read_text(encoding="utf-8"))

    files = []
    for data_set in report.get("data", []):
        files.extend(data_set.get("files", []))

    relevant = [
        entry
        for entry in files
        if is_linguistic_frontend_source(entry.get("filename", ""))
    ]
    if not relevant:
        print("TST-001: LLVM report contained no linguistic-front-end source files", file=sys.stderr)
        return 1

    line_count = sum(entry["summary"]["lines"]["count"] for entry in relevant)
    covered = sum(entry["summary"]["lines"]["covered"] for entry in relevant)
    if line_count == 0:
        print("TST-001: linguistic-front-end line count was zero", file=sys.stderr)
        return 1

    percentage = covered / line_count * 100
    print(
        f"TST-001 linguistic-front-end coverage: {covered}/{line_count} "
        f"lines ({percentage:.2f}%), required {minimum:.2f}%"
    )
    return 0 if percentage >= minimum else 1


if __name__ == "__main__":
    raise SystemExit(main())
