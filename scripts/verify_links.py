#!/usr/bin/env python3
"""
Internal Markdown & HTML Link Validator for DTN Mesh Algorithm Project.
Verifies that all relative markdown links inside docs/ point to valid existing target files.
"""

import sys
import re
from pathlib import Path

def main():
    root_dir = Path(__file__).resolve().parent.parent
    docs_dir = root_dir / "docs"

    if not docs_dir.exists():
        print("Error: docs/ directory does not exist!", file=sys.stderr)
        sys.exit(1)

    print(f"Validating relative links across {docs_dir}...")
    broken_links = []
    total_checked = 0

    # Match markdown links: [label](relative_path#anchor)
    link_regex = re.compile(r'\[([^\]]+)\]\(([^:\)]+)\)')

    for md_file in sorted(docs_dir.rglob("*.md")):
        text = md_file.read_text(encoding="utf-8")
        rel_md_path = md_file.relative_to(root_dir)

        for match in link_regex.finditer(text):
            label, link_target = match.groups()
            
            # Skip empty links, mailto, or external URIs
            if not link_target or link_target.startswith(("http://", "https://", "mailto:", "ftp://")):
                continue

            # Separate path and optional #anchor
            parts = link_target.split('#', 1)
            path_part = parts[0]
            anchor_part = parts[1] if len(parts) > 1 else None

            if not path_part:
                # Same-page anchor link, e.g. #section-name
                continue

            # Resolve target relative to the markdown file's directory
            resolved_target = (md_file.parent / path_part).resolve()

            total_checked += 1

            if not resolved_target.exists():
                broken_links.append((rel_md_path, link_target, f"Target file '{resolved_target}' does not exist"))

    if broken_links:
        print(f"\nFound {len(broken_links)} broken relative link(s):")
        for src, link, err in broken_links:
            print(f"  ✗ In {src}: link '{link}' -> {err}")
        sys.exit(1)

    print(f"✓ All {total_checked} relative links successfully verified!")
    sys.exit(0)

if __name__ == "__main__":
    main()
