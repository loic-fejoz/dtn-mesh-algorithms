#!/usr/bin/env bash
set -euo pipefail

# Ensure script directory exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Preparing documentation build in ${ROOT_DIR}/docs ==="

# 1. Copy CDDL files to docs/ so MkDocs includes them in navigation
for cddl_file in "${ROOT_DIR}"/*.cddl; do
  if [ -f "${cddl_file}" ]; then
    cp "${cddl_file}" "${ROOT_DIR}/docs/"
  fi
done

# 3. Create a copy of policies directory inside docs for code relative links
rm -rf "${ROOT_DIR}/docs/policies"
cp -r "${ROOT_DIR}/policies" "${ROOT_DIR}/docs/policies"

# 4. Fix relative README links inside docs/ markdown files so MkDocs resolves them to index.md/index.en.md
for doc in "${ROOT_DIR}/docs"/*.md; do
  if [ -f "${doc}" ]; then
    sed -i 's|\./README\.en\.md|\./index\.en\.md|g' "${doc}"
    sed -i 's|\./README\.md|\./index\.md|g' "${doc}"
  fi
done

echo "Documentation preparation complete."
