#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: pnpm package:arch [--install]\n'
}

fail() {
  printf 'package:arch: %s\n' "$*" >&2
  exit 1
}

install_package=false
case "$#:${1:-}" in
  0:) ;;
  1:--install) install_package=true ;;
  1:-h|1:--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

[[ $(uname -s) == Linux ]] || fail 'Arch packaging requires Linux.'
[[ $(uname -m) == x86_64 ]] || fail 'The OpenIDEA Arch recipe requires x86_64.'
(( EUID != 0 )) || fail 'Run this command as a regular user. makepkg cannot run as root.'

repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P) ||
  fail 'Could not resolve the OpenIDEA repository root.'
[[ $(pwd -P) == "$repo_root" && -f package.json && -f Cargo.toml ]] ||
  fail 'Run pnpm package:arch from the OpenIDEA repository root.'
recipe="$repo_root/packaging/arch"
manifest="$repo_root/src-tauri/Cargo.toml"
for file in "$manifest" "$repo_root"/src-tauri/tauri{,.linux}.conf.json \
  "$recipe"/{PKGBUILD,openidea.desktop,openidea.sh}; do
  [[ -f $file && -r $file ]] || fail "Missing or unreadable checkout file $file."
done

required_tools=(pnpm node cargo makepkg pacman fakeroot bsdtar jq brotli python3 zstd flock sha256sum cmp)
if "$install_package"; then
  required_tools+=(sudo)
fi
for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null || fail "Required command $tool is missing. Install it and rerun pnpm package:arch."
done

output_dir="$repo_root/target/arch"
mkdir -p -- "$output_dir" || fail "Could not create the package output directory $output_dir."
# The Tauri build and recipe share this checkout's dist directory.
exec {lock_fd}>"$output_dir/.lock" || fail "Could not open the Arch packaging lock in $output_dir."
flock -n "$lock_fd" || fail 'Could not acquire the Arch packaging lock. Check for another packaging run.'

stage_dir=$(mktemp -d -- "$output_dir/.build.XXXXXX") ||
  fail "Could not create a private makepkg directory in $output_dir."
trap 'rm -rf -- "$stage_dir"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

build_log="$stage_dir/build.log"
# Keep the configured frontend hook and capture Cargo's artifact paths from this build.
pnpm tauri build --no-bundle -- --message-format=json-render-diagnostics |
  tee "$build_log" | sed -u '/^{"reason":/d' ||
  fail 'Tauri release build failed. See the build output above.'

build_paths=$(jq -Rse --arg manifest "$manifest" '
  [split("\n")[] | fromjson? | objects] as $events
  | [$events[] | select(
      .reason == "compiler-artifact" and .manifest_path == $manifest
      and .target.name == "openidea" and .target.kind == ["bin"]
    ) | select(.executable | type == "string")] | unique_by(.executable)
  | if length == 1 then .[0] else error("Expected exactly one OpenIDEA release executable from Cargo") end
  | . as $binary
  | [$events[] | select(.reason == "build-script-executed" and .package_id == $binary.package_id)
    | .out_dir | strings] | unique
  | if length == 1 then {executable: $binary.executable, out_dir: .[0]}
    else error("Expected exactly one OpenIDEA build-script OUT_DIR from Cargo") end
' "$build_log") || fail 'Could not locate the OpenIDEA release artifacts from the Tauri build.'

release_binary=$(jq -r '.executable' <<< "$build_paths")
[[ $release_binary == /*/release/openidea && -f $release_binary && -s $release_binary && -x $release_binary ]] ||
  fail "Missing executable release binary at $release_binary."
source_checksum=$(sha256sum < "$release_binary") || fail "Could not hash the release executable $release_binary."
staged_binary="$stage_dir/openidea"
cp -- "$release_binary" "$staged_binary" || fail "Could not stage the release executable from $release_binary."
if ! source_checksum_after=$(sha256sum < "$release_binary") || [[ $source_checksum_after != "$source_checksum" ]]; then
  fail "The release executable at $release_binary changed or could not be verified during staging. Wait for any concurrent build to finish, then rerun pnpm package:arch."
fi
if ! staged_checksum=$(sha256sum < "$staged_binary") || [[ $staged_checksum != "$source_checksum" ]]; then
  fail "The staged release executable at $staged_binary differs from the original checksum or could not be verified. Wait for any concurrent build to finish, then rerun pnpm package:arch."
fi

build_out=$(jq -r '.out_dir' <<< "$build_paths")
dist="$repo_root/dist"
index="$dist/index.html"
[[ -f $index && -s $index ]] || fail "Missing frontend index at $index. Check the Tauri frontend build."
asset=$(LC_ALL=C grep -oE '[[:space:]]src="/assets/index-[A-Za-z0-9_-]{8,}\.js"' "$index" | sort -u) ||
  fail "No hashed JavaScript entry found in $index."
[[ $asset != *$'\n'* ]] || fail "Expected exactly one hashed JavaScript entry in $index."
asset=${asset#*src=\"}
asset=${asset%\"}
frontend_file="$dist$asset"
[[ -f $frontend_file && -s $frontend_file ]] || fail "Missing frontend JavaScript at $frontend_file."

codegen_dir="$build_out/tauri-codegen-assets"
[[ $build_out == /* && -d $codegen_dir ]] || fail "Missing Tauri codegen asset directory at $codegen_dir."
blob_matches_frontend() {
  brotli -d -c -- "$1" | cmp -s -- "$frontend_file" -
}

blob=
shopt -s nullglob
for candidate in "$codegen_dir"/*.js; do
  [[ -f $candidate && -s $candidate ]] || continue
  if blob_matches_frontend "$candidate" 2>/dev/null; then
    [[ -z $blob ]] || fail "More than one Tauri Brotli asset matches $asset in $codegen_dir."
    blob=$candidate
  fi
done
[[ -n $blob ]] || fail "No Tauri Brotli asset matches $asset in $codegen_dir."

staged_blob="$stage_dir/frontend.br"
cp -- "$blob" "$staged_blob" || fail "Could not stage the Tauri frontend blob from $blob."
blob_matches_frontend "$staged_blob" || fail "The staged Tauri Brotli asset no longer matches $frontend_file."
cp -- "$recipe"/{PKGBUILD,openidea.desktop,openidea.sh} "$stage_dir/" ||
  fail "Could not copy the Arch recipe files from $recipe."
printf '%s\n' "${staged_checksum%% *}" > "$stage_dir/openidea-tauri-production.sha256" ||
  fail "Could not write the Tauri production marker in $stage_dir."

# Command-line assignments take precedence over a user's makepkg.conf paths.
(
  cd -- "$stage_dir" &&
    OPENIDEA_REPO_ROOT="$repo_root" OPENIDEA_RELEASE_BINARY="$staged_binary" \
      OPENIDEA_FRONTEND_ASSET="$asset" OPENIDEA_FRONTEND_BLOB="$staged_blob" \
      makepkg --nosign "PKGDEST=$stage_dir" "BUILDDIR=$stage_dir" "SRCDEST=$stage_dir" \
        "SRCPKGDEST=$stage_dir" "LOGDEST=$stage_dir" 'PKGEXT=.pkg.tar.zst'
) || fail 'makepkg failed. See the packaging output above.'

archives=("$stage_dir"/*.pkg.tar.zst)
[[ ${#archives[@]} == 1 && -f ${archives[0]} && -s ${archives[0]} ]] ||
  fail 'makepkg finished, but the wrapper expected one nonempty .pkg.tar.zst archive.'
package="$output_dir/${archives[0]##*/}"
mv -fT -- "${archives[0]}" "$package" || fail "Could not preserve the package at $package."
printf 'Package: %s\n' "$package"

if "$install_package"; then
  sudo pacman -U -- "$package" || fail "pacman installation failed. The package is available at $package."
  installed=$(pacman -Q openidea) || fail 'pacman completed the install but could not report the installed OpenIDEA version.'
  printf 'Installed %s at /usr/bin/openidea\n' "$installed"
fi
