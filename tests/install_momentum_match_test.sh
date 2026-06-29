#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

assert_file_contains() {
  local file="$1" needle="$2"
  grep -Fq "$needle" "$file" || fail "expected $file to contain: $needle"
}

run_install_level() {
  local selected="$1" expected_level="$2" expected_name="$3"
  local home output
  home="$(mktemp -d)"
  output="$(env HOME="$home" bash "$ROOT/install.sh" --level "$selected" 2>&1)"

  assert_not_contains "$output" "WARN: invalid trust level"
  assert_contains "$output" "Trust level: $expected_level ($expected_name)"
  assert_contains "$output" "Done. The workflow OS is installed"

  rm -rf "$home"
}

assert_file_contains "$ROOT/install.sh" "Momentum Match"
assert_file_contains "$ROOT/install.sh" "A) Ship Mode"
assert_file_contains "$ROOT/install.sh" "B) Co-Pilot Mode"
assert_file_contains "$ROOT/install.sh" "C) Glass Box Mode"

run_install_level A 1 "Hands-off"
run_install_level b 2 "Watch commands"
run_install_level C 3 "Ask first"

printf 'PASS: install Momentum Match parity\n'
