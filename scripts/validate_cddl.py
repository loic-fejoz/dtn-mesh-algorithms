#!/usr/bin/env python3
"""
CDDL Schema Validator for DTN Mesh Algorithm Project.
Uses pycddl (Rust cddl-rs bindings) to validate all CDDL specification files.
"""

import sys
import glob
from pathlib import Path

try:
    import pycddl
except ImportError:
    print("Error: pycddl package is required. Install with: pip install pycddl", file=sys.stderr)
    sys.exit(1)


def main():
    root_dir = Path(__file__).resolve().parent.parent
    cddl_files = sorted(root_dir.glob("*.cddl"))

    if not cddl_files:
        print("No .cddl files found!")
        sys.exit(1)

    print(f"Validating {len(cddl_files)} CDDL schema files...")
    failed_files = []

    for cddl_path in cddl_files:
        rel_path = cddl_path.relative_to(root_dir)
        try:
            content = cddl_path.read_text(encoding="utf-8")
            pycddl.Schema(content)
            print(f"  ✓ {rel_path}: Valid CDDL RFC 8610 schema")
        except Exception as err:
            print(f"  ✗ {rel_path}: Invalid CDDL schema")
            print(f"    Details: {err}")
            failed_files.append(rel_path)

    if failed_files:
        print(f"\nValidation failed for {len(failed_files)} file(s).")
        sys.exit(1)

    print(f"\nAll {len(cddl_files)} CDDL schema files successfully validated!")
    sys.exit(0)


if __name__ == "__main__":
    main()
