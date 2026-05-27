#!/usr/bin/env bash
set -euo pipefail

suite_list="$(mktemp "${TMPDIR:-/tmp}/riptide-swift-testing-suites.XXXXXX")"
trap 'rm -f "$suite_list"' EXIT

swift test list --disable-xctest \
  | awk -F/ '/^RiptideTests\./ { print $1 }' \
  | sort -u > "$suite_list"

while IFS= read -r suite; do
  [ -n "$suite" ] || continue
  echo "::group::$suite"
  swift test --disable-xctest --filter "$suite"
  echo "::endgroup::"
done < "$suite_list"
