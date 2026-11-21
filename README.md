<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="src-tauri/icons/source/openidea-wordmark-dark.svg">
    <img src="src-tauri/icons/source/openidea-wordmark.svg" alt="OpenIDEA" height="56">
  </picture>
</p>

<p align="center">
  The IDE you know, rebuilt in Rust.
</p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a> · <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <a href="https://github.com/l0ng-ai/openidea/releases/latest"><b>Download</b></a>
  &nbsp;·&nbsp;
  <a href="https://openidea.sh">Docs</a>
  &nbsp;·&nbsp;
  <a href="#benchmark">Benchmark</a>
  &nbsp;·&nbsp;
  <a href="#plugins">Plugins</a>
  &nbsp;·&nbsp;
  <a href="#community">Community</a>
</p>

https://github.com/user-attachments/assets/234dd54c-1255-4b3a-b35c-533d78d737c0

OpenIDEA brings the IntelliJ IDEA way of working — its keymap, its tool windows,
its search-everything habits — to a native app with a Rust core.

Editor, code insight, debugger, Git, terminal, database and HTTP clients,
for 60+ languages. Builds for macOS, Windows and Linux.

On macOS you can also install it with Homebrew:

```bash
brew install --cask l0ng-ai/tap/openidea
```

## Deploy on Arch Linux

This x86_64 workflow builds a local Arch `.pkg.tar.zst` from your checkout.
Pacman owns the installed files system-wide. This workflow does not produce
`.deb`, `.rpm`, or AppImage bundles or use the AUR or `yay`.

Set up Rust, Node.js, pnpm, and the Arch system libraries for Tauri. Install
the package recipe's `depends` and `makedepends` before building. Run the
commands below from the repository root as a regular user. See the
[development setup](docs/en/contribute/setup.mdx), [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/#linux),
and [Arch package recipe](packaging/arch/PKGBUILD).

### Build the package

```sh
pnpm install --frozen-lockfile
pnpm package:arch
```

`pnpm package:arch` runs a Tauri release build with `--no-bundle` and writes
`target/arch/openidea-<version>-1-x86_64.pkg.tar.zst` without installing it.

### Install or upgrade

From your existing checkout, pull changes and rebuild the package. `--install`
runs `sudo pacman -U` on the archive after a successful build.

```sh
git pull --ff-only
pnpm install --frozen-lockfile
pnpm package:arch --install
openidea
```

The command is installed at `/usr/bin/openidea`, the app files are in
`/usr/lib/openidea`, and the menu entry is
`/usr/share/applications/openidea.desktop`.

### Uninstall

```sh
sudo pacman -R openidea
```

### Troubleshoot launching from Cinnamon

Search for **OpenIDEA** in the Cinnamon menu. If it is missing or clicking it
does nothing, run these checks from a terminal in your Cinnamon session.

```sh
pacman -Qkk openidea
command -v openidea
/usr/bin/openidea
```

- If pacman reports missing package files, rerun `pnpm package:arch --install`.
- If `command -v openidea` points somewhere other than `/usr/bin/openidea`,
  use the absolute path above to test the packaged launcher. Its terminal
  output can show errors that the menu hides.
- If the terminal launch works, check for an older `openidea.desktop` in
  `${XDG_DATA_HOME:-$HOME/.local/share}/applications/` that may take precedence
  over the system entry. Move any stale override out of that directory. If
  the entry still does not appear, sign out of Cinnamon and back in.
  See the [desktop entry precedence rules](https://specifications.freedesktop.org/desktop-entry/latest-single/#desktop-file-id).

## Benchmark

Opening [freqtrade](https://github.com/freqtrade/freqtrade) (Python, ~770 files)
with warm caches, median of 5 runs:

|                             | OpenIDEA          | IntelliJ IDEA 2026.2.3 |
| --------------------------- | ----------------- | ---------------------- |
| Window with the project     | **0.9 s**         | 3.1 s                  |
| Ready (CPU settled)         | **1.1 s**         | 13.2 s                 |
| Memory (USS, all processes) | **169 MB**        | 2011 MB                |
| CPU time until ready        | **2.4 s**         | 47.9 s                 |
| Idle CPU                    | **4 %** of a core | 7 % of a core          |
| Quit                        | **0.3 s**         | 5.9 s                  |

A release build of OpenIDEA from `main` and IDEA with default settings and plugins, on
Windows 11, 32-core AMD, 62 GB RAM.
IDEA analyses Python more deeply, so "ready" doesn't mean the same work on
both sides. Both are measured from the outside, the same way: see
[`perf/compare`](perf/compare) to run it on your machine and projects.

## Plugins

Plugins add actions, completion, quick fixes, tool windows, custom editors,
themes, file icons and languages. They run as sandboxed WebAssembly components;
themes, icon themes and languages need no code at all.

Install them from Settings › Plugins, or start your own with
`openidea-plugin new` — see [Writing OpenIDEA plugins](https://openidea.sh/en/plugins) and
the [official plugins](plugins/official). The plugin API is still a preview.

## Community

- [Discord](https://discord.gg/2Zy4yn7gP) — questions, feedback and release news.
- WeChat group — scan to join:

  <img src=".github/assets/wechat-group-4.png" alt="WeChat group QR code" width="200">

- Contributing: see [CONTRIBUTING.md](CONTRIBUTING.md) and the [contributor docs](https://openidea.sh/en/contribute/setup).

## License

[Apache 2.0](LICENSE). Bundled third-party assets are listed in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md).

<sub>Not affiliated with JetBrains. IntelliJ IDEA is a trademark of JetBrains s.r.o.</sub>
