// @vitest-environment node
import { execFile } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { brotliCompressSync } from "node:zlib";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

const bash = "/bin/bash";
const archive = "openidea-1.2.3-1-x86_64.pkg.tar.zst";
const checkoutFiles = [
  "Cargo.toml",
  "package.json",
  "src-tauri/Cargo.toml",
  "src-tauri/tauri.conf.json",
  "src-tauri/tauri.linux.conf.json",
  "packaging/arch/PKGBUILD",
  "packaging/arch/openidea.desktop",
  "packaging/arch/openidea.sh",
];
const linux = process.platform === "linux";
const supportsPackaging = linux && process.arch === "x64" && process.getuid?.() !== 0;
const hasJq = linux && existsSync("/usr/bin/jq");
const hasBrotli = linux && existsSync("/usr/bin/brotli");

describe.skipIf(!linux)("Arch packaging wrapper", () => {
  let root: string;
  let bin: string;
  let script: string;

  beforeEach(() => {
    root = mkdtempSync(join(realpathSync(tmpdir()), "openidea arch test-"));
    bin = join(root, "bin");
    script = join(root, "scripts/package-arch.sh");
    mkdirSync(bin);
    mkdirSync(dirname(script));
    copyFileSync(new URL("./package-arch.sh", import.meta.url), script);
    copyFileSync(
      new URL("./package-arch-artifacts.jq", import.meta.url),
      join(root, "scripts/package-arch-artifacts.jq"),
    );
  });

  afterEach(() => rmSync(root, { recursive: true, force: true }));

  async function run(args: string[], cwd = root) {
    const result = await new Promise<{ status: number; stdout: string; stderr: string }>((resolve, reject) => {
      execFile(
        bash,
        [script, ...args],
        { cwd, env: { PATH: bin, LC_ALL: "C", FIXTURE_ROOT: root }, encoding: "utf8", timeout: 4_000 },
        (error, stdout, stderr) => {
          const status = error ? error.code : 0;
          if (typeof status !== "number") {
            reject(error);
            return;
          }
          resolve({ status, stdout, stderr });
        },
      );
    });
    const unexpected = join(root, "unexpected-call");
    if (existsSync(unexpected)) throw new Error(`Unexpected tool invocation: ${readFileSync(unexpected, "utf8")}`);
    return result;
  }

  function stub(tool: string, body: string) {
    writeFileSync(join(bin, tool), `#!${bash}\nset -eu\n${body}\n`, { mode: 0o755 });
  }

  function unexpectedTool(tool: string) {
    stub(tool, 'printf "%s\\n" "$0" >> "$FIXTURE_ROOT/unexpected-call"; exit 97');
  }

  function readArgs(log: string) {
    return readFileSync(join(root, log), "utf8").split("\0").slice(0, -1);
  }

  it.each(["-h", "--help"])("prints usage for %s before checking tools or checkout files", async (flag) => {
    expect(await run([flag])).toMatchObject({
      status: 0,
      stdout: "Usage: pnpm package:arch [--install]\n",
      stderr: "",
    });
    expect(existsSync(join(root, "target"))).toBe(false);
  });

  it.each([{ args: ["--dry-run"] }, { args: ["--install", "extra"] }, { args: ["--help", "--install"] }])(
    "rejects invalid arguments $args before starting a build",
    async ({ args }) => {
      expect(await run(args)).toMatchObject({
        status: 2,
        stdout: "",
        stderr: "Usage: pnpm package:arch [--install]\n",
      });
      expect(existsSync(join(root, "target"))).toBe(false);
    },
  );

  describe.skipIf(!supportsPackaging)("on x86_64 Linux as a regular user", () => {
    beforeEach(() => {
      for (const file of checkoutFiles) {
        mkdirSync(dirname(join(root, file)), { recursive: true });
        writeFileSync(join(root, file), "");
      }
      for (const tool of [
        "uname",
        "dirname",
        "mkdir",
        "flock",
        "mktemp",
        "rm",
        "tee",
        "sed",
        "cat",
        "sha256sum",
        "cp",
        "grep",
        "sort",
        "cmp",
        "mv",
      ]) {
        symlinkSync(join("/usr/bin", tool), join(bin, tool));
      }
      for (const tool of ["node", "cargo", "pacman", "fakeroot", "bsdtar", "python3", "zstd"]) {
        unexpectedTool(tool);
      }
      for (const [tool, available] of [
        ["jq", hasJq],
        ["brotli", hasBrotli],
      ] as const) {
        if (available) symlinkSync(join("/usr/bin", tool), join(bin, tool));
        else unexpectedTool(tool);
      }
      unexpectedTool("pnpm");
      unexpectedTool("makepkg");
    });

    it("requires the checkout root as the working directory", async () => {
      expect(await run([], join(root, "scripts"))).toMatchObject({
        status: 1,
        stderr: expect.stringContaining("from the OpenIDEA repository root"),
      });
      expect(existsSync(join(root, "target"))).toBe(false);
    });

    it("identifies a missing checkout file", async () => {
      const desktop = join(root, "packaging/arch/openidea.desktop");
      rmSync(desktop);
      expect(await run([])).toMatchObject({
        status: 1,
        stderr: expect.stringContaining(`Missing or unreadable checkout file ${desktop}`),
      });
      expect(existsSync(join(root, "target"))).toBe(false);
    });

    it("identifies a missing required tool before building", async () => {
      rmSync(join(bin, "makepkg"));
      expect(await run([])).toMatchObject({
        status: 1,
        stderr: expect.stringContaining("Required command makepkg is missing"),
      });
      expect(existsSync(join(root, "target"))).toBe(false);
    });

    it("requires sudo before building in install mode", async () => {
      expect(await run(["--install"])).toMatchObject({
        status: 1,
        stderr: expect.stringContaining("Required command sudo is missing"),
      });
      expect(existsSync(join(root, "target"))).toBe(false);
    });

    const asset = "assets/index-A1b2C3d4.js";
    const buildOut = "target/release/build/openidea/out";

    function fakeBuild(executable?: string) {
      const events = [{ reason: "build-script-executed", package_id: "fixture", out_dir: join(root, buildOut) }];
      const artifact = {
        reason: "compiler-artifact",
        package_id: "fixture",
        manifest_path: join(root, "src-tauri/Cargo.toml"),
        target: { name: "openidea", kind: ["bin"] },
        executable,
      };
      const lines = executable === undefined ? events : [...events, artifact];
      writeFileSync(join(root, "cargo.log"), `${lines.map((line) => JSON.stringify(line)).join("\n")}\n`);
      stub("pnpm", 'printf "%s\\0" "$@" > "$FIXTURE_ROOT/pnpm.args"\ncat "$FIXTURE_ROOT/cargo.log"');
    }

    it.skipIf(!hasJq || !hasBrotli)("builds and preserves one native archive by default without sudo", async () => {
      const executable = join(root, "target/release/openidea");
      const codegen = join(root, buildOut, "tauri-codegen-assets");
      const javascript = 'console.log("fixture");\n';
      mkdirSync(codegen, { recursive: true });
      mkdirSync(join(root, "dist/assets"), { recursive: true });
      writeFileSync(executable, "fixture executable\n", { mode: 0o755 });
      writeFileSync(join(root, "dist/index.html"), `<script type="module" src="/${asset}"></script>\n`);
      writeFileSync(join(root, "dist", asset), javascript);
      writeFileSync(join(codegen, "fixture.js"), brotliCompressSync(javascript));
      fakeBuild(executable);
      stub(
        "makepkg",
        `printf "%s\\0" "$PWD" "$@" > "$FIXTURE_ROOT/makepkg.args"\nprintf 'fixture package\\n' > '${archive}'`,
      );

      const output = join(root, "target/arch", archive);
      expect(await run([])).toMatchObject({ status: 0, stdout: `Package: ${output}\n`, stderr: "" });
      expect(readArgs("pnpm.args")).toEqual([
        "tauri",
        "build",
        "--no-bundle",
        "--",
        "--message-format=json-render-diagnostics",
      ]);
      const [stage, ...args] = readArgs("makepkg.args");
      expect(stage).toMatch(/\/target\/arch\/\.build\.[^/]+$/);
      expect(args).toEqual([
        "--nosign",
        `PKGDEST=${stage}`,
        `BUILDDIR=${stage}`,
        `SRCDEST=${stage}`,
        `SRCPKGDEST=${stage}`,
        `LOGDEST=${stage}`,
        "PKGEXT=.pkg.tar.zst",
      ]);
      expect(readFileSync(output, "utf8")).toBe("fixture package\n");
    });

    it.skipIf(!hasJq)("stops install mode when Cargo reports no release executable", async () => {
      fakeBuild();
      unexpectedTool("sudo");

      expect(await run(["--install"])).toMatchObject({
        status: 1,
        stderr: expect.stringContaining("Could not locate the OpenIDEA release artifacts"),
      });
    });

    it.skipIf(!hasJq)("stops install mode when the reported release binary is missing", async () => {
      const executable = join(root, "target/release/openidea");
      fakeBuild(executable);
      unexpectedTool("sudo");

      expect(await run(["--install"])).toMatchObject({
        status: 1,
        stderr: expect.stringContaining(`Missing executable release binary at ${executable}`),
      });
    });

    it.skipIf(!hasJq)("rejects a relative Cargo executable path even if it exists", async () => {
      const executable = "target/release/openidea";
      mkdirSync(join(root, "target/release"), { recursive: true });
      writeFileSync(join(root, executable), "fixture executable\n", { mode: 0o755 });
      fakeBuild(executable);
      unexpectedTool("sudo");

      expect(await run(["--install"])).toMatchObject({
        status: 1,
        stderr: expect.stringContaining(`Missing executable release binary at ${executable}`),
      });
    });
  });
});
