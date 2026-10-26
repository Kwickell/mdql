#!/usr/bin/env bash
# Downloads the JavaScript rendering engines into Resources/vendor, together
# with their licence texts, and records versions and hashes in
# Resources/vendor/MANIFEST.txt. The result is committed, so a normal build
# needs neither node nor the network.
#
# Every engine here is redistributed inside the app bundle, so its licence file
# has to travel with it. Adding a package means adding it to NPM_PKGS, which is
# what collects the licence.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Resources/vendor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

NPM_PKGS=(
  "markdown-it@14.1.0"
  "markdown-it-footnote@4.0.0"
  "markdown-it-deflist@3.0.0"
  "markdown-it-mark@4.0.0"
  "markdown-it-sub@2.0.0"
  "markdown-it-sup@2.0.0"
  "markdown-it-abbr@2.0.0"
  "markdown-it-task-lists@2.1.1"
  "markdown-it-texmath@1.0.0"
  "katex@0.16.11"
  "mermaid@11.4.1"
  # Its browser bundle comes from the CDN below; the package is unpacked here
  # only to collect the licence that covers it.
  "highlight.js@11.11.1"
)

CDN_FILES=(
  "highlight.min.js|https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js"
  "highlight-github.min.css|https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css"
  "highlight-github-dark.min.css|https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css"
)

rm -rf "$OUT"
mkdir -p "$OUT/katex/fonts" "$OUT/mermaid" "$OUT/licenses"

cd "$WORK"
for pkg in "${NPM_PKGS[@]}"; do
  echo "pack $pkg"
  tgz="$(npm pack "$pkg" --silent)"
  mkdir -p "x/${pkg%@*}"
  tar -xzf "$tgz" -C "x/${pkg%@*}" --strip-components=1
done

cp x/markdown-it/dist/markdown-it.min.js                   "$OUT/"
cp x/markdown-it-footnote/dist/markdown-it-footnote.min.js "$OUT/"
cp x/markdown-it-deflist/dist/markdown-it-deflist.min.js   "$OUT/"
cp x/markdown-it-mark/dist/markdown-it-mark.min.js         "$OUT/"
cp x/markdown-it-sub/dist/markdown-it-sub.min.js           "$OUT/"
cp x/markdown-it-sup/dist/markdown-it-sup.min.js           "$OUT/"
cp x/markdown-it-abbr/dist/markdown-it-abbr.min.js         "$OUT/"
cp x/markdown-it-task-lists/dist/markdown-it-task-lists.min.js "$OUT/" 2>/dev/null \
  || cp x/markdown-it-task-lists/index.js "$OUT/markdown-it-task-lists.min.js"

cp x/katex/dist/katex.min.js              "$OUT/katex/"
cp x/katex/dist/katex.min.css             "$OUT/katex/"
cp x/markdown-it-texmath/texmath.js       "$OUT/markdown-it-texmath.js"
cp x/markdown-it-texmath/css/texmath.css  "$OUT/texmath.css"
cp x/katex/dist/fonts/*.woff2             "$OUT/katex/fonts/"

# The minified UMD build is self-contained; the ESM entry points next to it
# would only add weight.
cp x/mermaid/dist/mermaid.min.js "$OUT/mermaid/"

for pkg in "${NPM_PKGS[@]}"; do
  name="${pkg%@*}"
  found=""
  for candidate in LICENSE LICENSE.md LICENSE.txt LICENCE License license LICENSE-MIT COPYING; do
    if [[ -f "x/$name/$candidate" ]]; then
      cp "x/$name/$candidate" "$OUT/licenses/$name.LICENSE"
      found="yes"
      break
    fi
  done
  [[ -n "$found" ]] || { echo "no licence file in $pkg" >&2; exit 1; }
done

for entry in "${CDN_FILES[@]}"; do
  name="${entry%%|*}"; url="${entry#*|}"
  echo "fetch $name"
  curl -fsSL --max-time 60 -o "$OUT/$name" "$url"
done

{
  echo "# Vendored rendering engines. Regenerate with tools/vendor.sh."
  echo "# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  for pkg in "${NPM_PKGS[@]}"; do echo "npm  $pkg"; done
  for pkg in "${NPM_PKGS[@]}"; do
  name="${pkg%@*}"
  found=""
  for candidate in LICENSE LICENSE.md LICENSE.txt LICENCE License license LICENSE-MIT COPYING; do
    if [[ -f "x/$name/$candidate" ]]; then
      cp "x/$name/$candidate" "$OUT/licenses/$name.LICENSE"
      found="yes"
      break
    fi
  done
  [[ -n "$found" ]] || { echo "no licence file in $pkg" >&2; exit 1; }
done

for entry in "${CDN_FILES[@]}"; do echo "cdn  ${entry#*|}"; done
  echo
  cd "$OUT" && find . -type f ! -name MANIFEST.txt | sort | while read -r f; do
    echo "$(shasum -a 256 "$f" | cut -d' ' -f1)  ${f#./}"
  done
} > "$OUT/MANIFEST.txt"

echo "vendored $(find "$OUT" -type f | wc -l | tr -d ' ') files, $(du -sh "$OUT" | cut -f1)"
echo "licences:   $(find "$OUT/licenses" -type f | wc -l | tr -d ' ')"
