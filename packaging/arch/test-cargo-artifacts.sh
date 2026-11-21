#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
suite=$(mktemp -d "${TMPDIR:-/tmp}/openidea arch artifacts.XXXXXX")
trap 'rm -rf -- "$suite"' EXIT
cd -P -- "$suite"

mkdir -p bin scripts packaging/arch src-tauri dist/assets \
  target/release/build/openidea/out/tauri-codegen-assets
cp "$repo/scripts/package-arch.sh" scripts/
ln -s "$repo/scripts/package-arch-artifacts.jq" scripts/
touch package.json Cargo.toml src-tauri/{Cargo.toml,tauri.conf.json,tauri.linux.conf.json} \
  packaging/arch/{PKGBUILD,openidea.desktop,openidea.sh}
printf 'fixture executable\n' > target/release/openidea
chmod +x target/release/openidea
printf '<script type="module" src="/assets/index-A1b2C3d4.js"></script>\n' > dist/index.html
printf 'console.log("fixture");\n' > dist/assets/index-A1b2C3d4.js
brotli -c dist/assets/index-A1b2C3d4.js > target/release/build/openidea/out/tauri-codegen-assets/fixture.js

false_path=$(type -P false)
for tool in node cargo pacman fakeroot bsdtar python3 zstd sudo; do
  ln -s "$false_path" "bin/$tool"
done
export PATH="$PWD/bin:$PATH"

pnpm() {
  [[ $# == 5 && $* == 'tauri build --no-bundle -- --message-format=json-render-diagnostics' ]] || return 1
  # Shift Bash's read offset by editing the running wrapper in place.
  sed '2s/$/        /' scripts/package-arch.sh > updated.sh
  cat updated.sh > scripts/package-arch.sh
  cat <<EOF
Finished release profile
{"reason":"build-script-executed","package_id":"registry+https://example.com/index#other@1.0.0","out_dir":"$PWD/target/release/build/other/out"}
{"reason":"compiler-artifact","package_id":"registry+https://example.com/index#other@1.0.0","manifest_path":"$PWD/other/Cargo.toml","target":{"name":"openidea","kind":["bin"]},"executable":"$PWD/target/release/deps/openidea"}
{"reason":"build-script-executed","package_id":"path+file:///fixture/src-tauri#openidea@0.1.50","out_dir":"$PWD/target/release/build/openidea/out"}
{"reason":"compiler-artifact","package_id":"path+file:///fixture/src-tauri#openidea@0.1.50","manifest_path":"$PWD/src-tauri/Cargo.toml","target":{"name":"openidea","kind":["bin"]},"executable":"$PWD/target/release/openidea"}
{"reason":"build-finished","success":true}
EOF
}

makepkg() {
  cmp "$OPENIDEA_RELEASE_BINARY" "$OPENIDEA_REPO_ROOT/target/release/openidea" || return 1
  printf 'fixture package\n' > openidea-fixture-x86_64.pkg.tar.zst
}
export -f pnpm makepkg

bash scripts/package-arch.sh
[[ -s target/arch/openidea-fixture-x86_64.pkg.tar.zst ]]
printf 'PASS Cargo artifacts after an in-place wrapper edit\n'
