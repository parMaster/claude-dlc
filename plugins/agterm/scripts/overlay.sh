#!/usr/bin/env bash
# Open an HTML file or a URL in an agterm overlay over the caller's own
# session. Only ever runs `agtermctl session overlay open` against
# $AGTERM_SESSION_ID — approve-overlay.sh auto-approves calls to this script on
# the strength of that. Markdown goes to webrev.py instead.
#
# Usage: overlay.sh html <file> [--js]
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
    die "usage: overlay.sh html <file> [--js] | url <url> [--js]"
    ;;
esac
