#!/bin/bash
# Static checks for the plugin. Needs bash, jq and python3
# (shellcheck and qmllint are used when installed).

# `cond && pass || fail` is safe here: pass() always returns 0.
# shellcheck disable=SC2015

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

failures=0
pass() { printf '  ok    %s\n' "$1"; return 0; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
section() { printf '\n%s\n' "$1"; }

section "Manifest"
jq -e . manifest.json >/dev/null 2>&1 && pass "manifest.json is valid JSON" || fail "manifest.json is not valid JSON"
jq -e '.schemaVersion == 1' manifest.json >/dev/null && pass "schemaVersion is 1" || fail "schemaVersion must be 1"
id=$(jq -r .id manifest.json)
grep -q "\"$id\"" Panel.qml && pass "Panel.qml moduleName matches id" || fail "moduleName does not match manifest id"
while IFS= read -r entry; do
  [[ -f $entry ]] && pass "entry point $entry exists" || fail "missing entry point: $entry"
done < <(jq -r '.entryPoints[]' manifest.json)
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate . >/dev/null 2>&1 && pass "omarchy plugin validate" || fail "omarchy plugin validate"
fi

section "Translations"
en_keys=$(jq -r 'keys[]' i18n/en.json | sort)
for f in i18n/*.json; do
  jq -e . "$f" >/dev/null 2>&1 || { fail "$f is not valid JSON"; continue; }
  d=$(diff <(echo "$en_keys") <(jq -r 'keys[]' "$f" | sort))
  [[ -z $d ]] && pass "$f has the same keys as en.json" || fail "$f keys differ: $(echo "$d" | tr '\n' ' ')"
done
missing=""
for key in $(grep -ohE 'tr\("[A-Za-z.]+"|tn\("[A-Za-z.]+"|"(error|state)\.[A-Za-z]+"' ./*.qml | grep -oE '[a-zA-Z]+\.[A-Za-z.]+' | sort -u); do
  jq -e --arg k "$key" 'has($k)' i18n/en.json >/dev/null || missing="$missing $key"
done
[[ -z $missing ]] && pass "every key used in QML exists in en.json" || fail "keys missing from en.json:$missing"

section "Untrusted text"
for f in ./*.qml; do
  texts=$(grep -cE '^\s*(component \w+: )?Text \{' "$f")
  plain=$(grep -cE 'textFormat: Text\.PlainText' "$f")
  (( plain >= texts )) && pass "$(basename "$f"): $texts Text element(s), all PlainText" \
    || fail "$(basename "$f"): $texts Text elements, only $plain PlainText"
done
if grep -nE 'execDetached\(\["(sh|bash)", "-c", "[^"]*" \+' ./*.qml; then
  fail "shell code built by string concatenation"
else
  pass "no values concatenated into shell code"
fi

section "Scripts"
for s in setup tests/check.sh tests/fake-dreame-vacuum cli/dreame-vacuum.py; do
  [[ -x $s ]] && pass "$s is executable" || fail "$s is not executable"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck setup tests/check.sh && pass "shellcheck" || fail "shellcheck"
fi
python3 -m py_compile cli/dreame-vacuum.py tests/fake-dreame-vacuum 2>/dev/null \
  && pass "python compiles" || fail "python does not compile"
python3 -I cli/dreame-vacuum.py --help >/dev/null && pass "dreame-vacuum --help" || fail "dreame-vacuum --help"

section "Fake CLI contract"
export XDG_RUNTIME_DIR
XDG_RUNTIME_DIR=$(mktemp -d)
fake=tests/fake-dreame-vacuum
"$fake" --output json --lang en status | jq -e '.ok and .data.configured and (.data.rooms | length > 0) and (.data.suctionOptions | length == 4)' >/dev/null \
  && pass "status" || fail "status"
"$fake" --output json start >/dev/null && "$fake" --output json status | jq -e '.data.running' >/dev/null \
  && pass "start" || fail "start"
"$fake" --output json suction turbo >/dev/null && "$fake" --output json status | jq -e '.data.suction == "turbo"' >/dev/null \
  && pass "suction" || fail "suction"
"$fake" --output json clean-rooms 2 --repeats 1 | jq -e '.ok' >/dev/null && pass "clean-rooms" || fail "clean-rooms"
"$fake" --output json suction loud >/dev/null && fail "accepts a bad suction level" || pass "rejects a bad suction level"
first=$(FAKE_WATCH_INTERVAL=0.1 timeout 1 "$fake" --output json watch | head -1)
jq -e '.data.activity' <<<"$first" >/dev/null && pass "watch" || fail "watch"
rm -rf "$XDG_RUNTIME_DIR"

shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
lint=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
if [[ -x $lint && -d $shell_dir/Ui ]]; then
  section "QML lint (with Omarchy shell imports)"
  imports=$(mktemp -d)
  trap 'rm -rf "$imports"' EXIT
  mkdir "$imports/qs"
  for module in "$shell_dir"/*/; do
    [[ -f $module/qmldir ]] && ln -s "$module" "$imports/qs/$(basename "$module")"
  done
  if out=$("$lint" -I "$imports" ./*.qml 2>&1 | grep -E '^(Warning|Error)' \
      | grep -v '\[unqualified\]' | grep -v 'not found on type "QObject"'); then
    fail "qmllint: $out"
  else
    pass "qmllint finds no type or property errors"
  fi
fi

printf '\n'
if (( failures )); then printf '%d check(s) failed\n' "$failures"; exit 1; fi
printf 'All checks passed\n'
