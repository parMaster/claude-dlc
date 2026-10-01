#!/usr/bin/env bash
# Open a markdown file (glow), an HTML file or a URL in an agterm overlay over
# the caller's own session. Only ever runs `agtermctl session overlay open|result`
# against $AGTERM_SESSION_ID — approve-overlay.sh auto-approves calls to this
# script on the strength of that.
#
# Usage: overlay.sh md [file]     # no file = newest plan in docs/plans/, then docs/plans/completed/
#        overlay.sh html <file> [--js]
#        overlay.sh url <url> [--js]

set -euo pipefail

die() { echo "overlay: $*" >&2; exit 1; }

[ -n "${AGTERM_SESSION_ID:-}" ] || die "not inside an agterm session (AGTERM_SESSION_ID is unset)"
command -v agtermctl >/dev/null 2>&1 || die "agtermctl not found on PATH"

kind="${1:-}"
arg="${2:-}"

abs_file() {
  [ -f "$1" ] || die "no such file: $1"
  (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")")
}

latest_plan() {
  local dir newest
  for dir in docs/plans docs/plans/completed; do
    # ls -t sorts by mtime; plan names never contain newlines.
    newest=$(ls -t "$dir"/*.md 2>/dev/null | head -1 || true)
    if [ -n "$newest" ]; then printf '%s' "$newest"; return; fi
  done
  die "no plans found in docs/plans/ or docs/plans/completed/"
}

open_overlay() {
  local err
  if ! err=$(agtermctl session overlay open "$@" --target "$AGTERM_SESSION_ID" 2>&1 >/dev/null); then
    # agterm refuses to replace an open overlay; closing it for the user could
    # kill a program they're in the middle of, so ask them to close it instead.
    case "$err" in
      *"already open"*) die "an overlay is already open in this session; close it (q or Cmd-W) and try again" ;;
      *) die "agtermctl: $err" ;;
    esac
  fi
}

case "$kind" in
  md)
    if [ -z "$arg" ]; then arg=$(latest_plan) || exit 1; fi
    file=$(abs_file "$arg") || exit 1
    # agterm shell-parses the command line; handing the path to zsh as $1 keeps
    # it to one level of quoting, so spaces and quotes in the path survive.
    printf -v quoted '%q' "$file"
    open_overlay "zsh -lc 'glow -p \"\$1\"' glow $quoted" --cwd "$(dirname "$file")" --size-percent 90
    # A glow that can't start (not on PATH, bad file) closes the overlay at
    # once, which looks like nothing happened; surface its exit code instead.
    sleep 1
    if status=$(agtermctl session overlay result --json --target "$AGTERM_SESSION_ID" 2>/dev/null); then
      code=$(printf '%s' "$status" | jq -r '.result.exitCode // empty')
      if [ -n "$code" ] && [ "$code" != 0 ]; then
        die "glow exited with status $code right after opening $file"
      fi
    fi
    echo "opened $file"
    ;;
  html)
    [ -n "$arg" ] || die "usage: overlay.sh html <file> [--js]"
    file=$(abs_file "$arg") || exit 1
    js=()
    [ "${3:-}" = "--js" ] && js=(--js)
    open_overlay --html "$file" --cwd "$(dirname "$file")" --navigation ${js[@]+"${js[@]}"} --size-percent 90
    echo "opened $file"
    ;;
  url)
    case "$arg" in
      http://*|https://*|file://*) ;;
      *) die "not an http(s):// or file:// URL: $arg" ;;
    esac
    js=()
    [ "${3:-}" = "--js" ] && js=(--js)
    open_overlay --url "$arg" ${js[@]+"${js[@]}"} --size-percent 90
    echo "opened $arg"
    ;;
  *)
    die "usage: overlay.sh md [file] | html <file> [--js] | url <url> [--js]"
    ;;
esac
