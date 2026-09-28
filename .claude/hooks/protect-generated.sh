#!/usr/bin/env bash
# Pre-edit hook: block hand edits to generated files. Exit 2 blocks the edit.
set -euo pipefail

FILE="$(jq --raw-output '.tool_input.file_path // empty')"

case "$FILE" in
  */app/package-lock.json | */.terraform.lock.hcl | */app/dist/*)
    echo "Generated file: regenerate it (npm install, terraform providers lock, npm run build) instead of editing." >&2
    exit 2
    ;;
  */docs/diagrams/*.svg | */docs/diagrams/*.png)
    echo "Exported diagram: edit the .drawio source and export again." >&2
    exit 2
    ;;
esac
exit 0
