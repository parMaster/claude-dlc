#!/usr/bin/env bash
# Build a self-contained HTML dashboard of the repo's docs/backlog/ items and
# print its path. Read-only for the repo: the page goes to the temp dir. Opening
# it is the caller's job, so the page works with or without agterm.
#
# Usage: backlog-dashboard.sh    # from anywhere inside the repo

set -euo pipefail

die() { echo "backlog-dashboard: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq not found on PATH"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a Git repository"
cd "$root"
[ -d docs/backlog ] || die "no docs/backlog/ in $root"

template="$(cd "$(dirname "$0")" && pwd)/backlog-dashboard.html"
[ -f "$template" ] || die "template missing: $template"

# Value of one frontmatter key; empty when the key or the frontmatter is absent.
fm() {
  awk -v k="$1" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 { sub(/^[^:]*:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }
  ' "$2"
}

# Everything below the frontmatter.
content() {
  awk '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---" { infm = 0; next }
    !infm { print }
  ' "$1"
}

items=$(mktemp)
trap 'rm -f "$items"' EXIT

for f in docs/backlog/*.md; do
  [ -f "$f" ] || continue
  slug=$(basename "$f" .md)
  text=$(content "$f")
  title=$(printf '%s\n' "$text" | awk '/^# / { sub(/^# +/, ""); print; exit }')
  body=$(printf '%s\n' "$text" | awk '!seen && /^# / { seen = 1; next } { print }')
  where=$(fm where "$f")

  # `where` is path:line; the line is optional and the path may itself hold a colon.
  path=$where line=""
  case "${where##*:}" in
    "$where" | "" | *[!0-9]*) ;;
    *) path=${where%:*} line=${where##*:} ;;
  esac

  missing=false area=unanchored
  if [ -n "$where" ]; then
    if [ ! -e "$path" ]; then
      missing=true
    elif [ -n "$line" ] && [ -f "$path" ] && [ "$line" -gt "$(awk 'END { print NR }' "$path")" ]; then
      missing=true
    fi
    dir=$(dirname "$path")
    if [ "$dir" = "." ]; then area=$path; else area=$(printf '%s' "$dir" | cut -d/ -f1-2); fi
  fi

  # No commit yet gives an empty date; the page shows that as uncommitted, not as an error.
  touched=$(git log -1 --format=%cs -- "$f" 2>/dev/null || true)
  uncommitted=false
  [ -z "$(git status --porcelain -- "$f")" ] || uncommitted=true

  jq -n --arg slug "$slug" --arg title "${title:-$slug}" --arg worth "$(fm worth "$f")" \
    --arg where "$where" --arg ticket "$(fm ticket "$f")" --arg added "$(fm added "$f")" \
    --arg body "$body" --arg area "$area" --arg touched "$touched" \
    --argjson whereMissing "$missing" --argjson uncommitted "$uncommitted" \
    '{slug: $slug, title: $title, worth: $worth, where: $where, ticket: $ticket, added: $added,
      body: $body, area: $area, touched: $touched, whereMissing: $whereMissing, uncommitted: $uncommitted}' \
    >> "$items"
done

[ -s "$items" ] || die "docs/backlog/ has no items"

branch=$(git branch --show-current)
commit=$(git rev-parse --short HEAD 2>/dev/null || true)
# Local ref only: a viewer should not need the network to find the default branch.
default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
default=${default#origin/}
off_default=false
if [ -n "$default" ] && [ "$branch" != "$default" ]; then off_default=true; fi

repo=$(basename "$root")
# Its own directory: the overlay grants the page read access to the file's whole folder.
safe=$(printf '%s' "$repo" | tr -c 'A-Za-z0-9._-' '_')
tmp=${TMPDIR:-/tmp}
out_dir="${tmp%/}/backlog-dashboard-${safe}-$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
mkdir -p "$out_dir"
out="$out_dir/index.html"

data=$(mktemp)
trap 'rm -f "$items" "$data"' EXIT
# Escaping every "<" keeps an item body from closing the data <script> early.
jq -c -s --arg repo "$repo" --arg branch "$branch" --arg commit "$commit" \
  --arg defaultBranch "$default" --argjson offDefault "$off_default" \
  '{repo: $repo, branch: $branch, commit: $commit, defaultBranch: $defaultBranch,
    offDefault: $offDefault, count: length, items: .}' "$items" \
  | sed 's/</\\u003c/g' > "$data"

awk -v datafile="$data" '
  $0 == "__BACKLOG_DATA__" { while ((getline line < datafile) > 0) print line; next }
  { print }
' "$template" > "$out"

echo "$out"
