#!/usr/bin/env bash
# Post-edit hook: format the file that was just written.
set -euo pipefail

FILE="$(jq --raw-output '.tool_input.file_path // empty')"
[ "$FILE" != "" ] && [ -f "$FILE" ] || exit 0

case "$FILE" in
  *.sh)
    if command -v shellharden > /dev/null 2>&1; then
      shellharden --replace "$FILE" || true
    fi
    if head -1 "$FILE" | grep -q '^#!'; then
      chmod +x "$FILE"
    fi
    ;;
  *.md)
    if command -v markdownlint-cli2 > /dev/null 2>&1; then
      markdownlint-cli2 --fix "$FILE" > /dev/null 2>&1 || true
    fi
    ;;
  *.tf | *.tftest.hcl)
    terraform fmt "$FILE" > /dev/null 2>&1 || true
    ;;
esac
