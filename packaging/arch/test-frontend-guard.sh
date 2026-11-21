#!/usr/bin/env bash
set -euo pipefail

recipe=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
suite=$(mktemp -d "${TMPDIR:-/tmp}/openidea arch guard.XXXXXX")
trap 'rm -rf -- "$suite"' EXIT

export OPENIDEA_REPO_ROOT="$suite/checkout"
export OPENIDEA_FRONTEND_ASSET=/assets/index-A1b2C3d4.js
export OPENIDEA_FRONTEND_BLOB="$suite/frontend.br"
dist="$OPENIDEA_REPO_ROOT/dist"
asset="$dist$OPENIDEA_FRONTEND_ASSET"
mkdir -p "$dist/assets"
ln -s "$recipe/../../src-tauri" "$OPENIDEA_REPO_ROOT/src-tauri"
for notice in LICENSE NOTICE THIRD_PARTY_LICENSES.md; do
  ln -s "$recipe/../../$notice" "$OPENIDEA_REPO_ROOT/$notice"
done
printf '<script type="module" src="%s"></script>\n' "$OPENIDEA_FRONTEND_ASSET" > "$dist/index.html"
# Keep NUL and newline bytes in the small test stream at quality 0.
printf '// JS comment with a NUL \000 and newline\nconsole.log("the actual frontend asset");\n' > "$asset"
brotli -q 0 -c -- "$asset" > "$OPENIDEA_FRONTEND_BLOB"

cd "$suite"
cat > fixture.c <<'C'
#include <stdio.h>

#ifdef EMBED_CONTENT
__asm__(".pushsection .rodata\n.incbin \"frontend.br\"\n.popsection");
#endif

int main(void) {
  puts("/assets/index-A1b2C3d4.js");
  return 0;
}
C
cc -o path-only fixture.c
cc -DEMBED_CONTENT -o with-content fixture.c
cp "$recipe/"{PKGBUILD,openidea.desktop,openidea.sh} .

run_case() (
  local name=$1 binary=$2 error=${3:-} log="$suite/$1.log" checksum
  export OPENIDEA_RELEASE_BINARY="$suite/$binary"
  local startdir=$suite pkgdir="$suite/stage-$name"
  checksum=$(sha256sum < "$OPENIDEA_RELEASE_BINARY")
  printf '%s\n' "${checksum%% *}" > "$startdir/openidea-tauri-production.sha256"

  # Run package() directly so the fixture needs no installed runtime dependencies.
  if (set -e; source "$startdir/PKGBUILD" && package) > "$log" 2>&1; then
    if [[ -n $error ]]; then
      printf 'FAIL %s: package() accepted the executable\n' "$name" >&2
      return 1
    fi
    cmp "$OPENIDEA_RELEASE_BINARY" "$pkgdir/usr/lib/openidea/openidea"
  else
    if [[ -z $error ]] || ! grep -Fq -- "$error" "$log"; then
      cat "$log" >&2
      printf 'FAIL %s: unexpected package() rejection\n' "$name" >&2
      return 1
    fi
  fi
  printf 'PASS %s\n' "$name"
)

run_case path-only path-only 'does not contain the built frontend content'
run_case with-content with-content
printf '\nconsole.log("this asset changed after linking");\n' >> "$asset"
run_case stale-content with-content 'does not match the built frontend asset'
