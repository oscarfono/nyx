# Known issues

Every workaround in this repo, why it exists, and when to check whether it
is still needed.

`nyx-doctor` parses this file: any entry whose **Retest at** version is
older than what is installed gets flagged, so workarounds do not quietly
outlive the bugs they work around.

Format matters — the field names are parsed, so keep them exactly as below.
Status is one of: `open`, `reported`, `fixed-upstream`, `wontfix`.

---

## waybar: workspace buttons do not respond to clicks

- **Status:** open
- **Project:** Alexays/Waybar
- **Component:** waybar
- **Retest at:** waybar 0.16.0
- **Workaround in:** home/desktop.nix, home/tools.nix (`nyx-ws`)
- **Upstream:**

Waybar's `hyprland/workspaces` module dispatches `on-click = "activate"`
over Hyprland's IPC using the pre-Lua dispatch syntax. Hyprland 0.55+ parses
dispatch arguments as Lua, so the call is rejected and nothing happens. No
error is logged because Waybar does not surface the IPC reply.

Keyboard binds are unaffected: those go through the Lua config directly.

Workaround: `nyx-ws next|prev|1-9` wired to `on-scroll-up`/`on-scroll-down`,
which run as plain commands rather than through the IPC dispatcher.

---

## eat: terminfo is not present in the straight build directory

- **Status:** open
- **Project:** akib/emacs-eat
- **Component:** emacs-eat
- **Retest at:** eat 0.10
- **Workaround in:** manual `tic` into straight/build, see below
- **Upstream:**

eat ships terminfo sources and expects them compiled into its build
directory. straight.el symlinks only `.el` files, so `TERMINFO` points at a
directory that does not exist, `eat-truecolor` is unknown to ncurses, and
programs fall back to broken cursor handling.

Workaround, re-run after any `straight-rebuild-package eat`:

```bash
mkdir -p ~/.emacs.d/straight/build/eat/terminfo
tic -x -o ~/.emacs.d/straight/build/eat/terminfo ~/.emacs.d/straight/repos/eat/eat.ti
```

Better fix: point `eat-term-terminfo-directory` at the repo copy in
`.emacs.d`, which survives rebuilds.

---

## ghostty: shell integration loads outside Ghostty

- **Status:** open
- **Project:** nix-community/home-manager
- **Component:** home-manager
- **Retest at:** home-manager 26.11
- **Workaround in:** home/default.nix (`programs.zsh.initContent`)
- **Upstream:**

Ghostty exports `GHOSTTY_RESOURCES_DIR` into the session, so Emacs and
everything it spawns inherits it. home-manager's generated `.zshrc` sources
Ghostty's shell integration whenever that path is readable — it guards on
the file existing, not on the terminal actually being Ghostty.

Inside Emacs `eat` that integration emits Ghostty-specific escape sequences
for cursor position and bracketed paste, which eat does not implement:
keystrokes duplicate on redraw and paste corrupts.

Workaround: unset `GHOSTTY_RESOURCES_DIR` when `$TERM != xterm-ghostty`,
before home-manager's block runs.

---

## maltego: Java detector dies on NixOS

- **Status:** wontfix
- **Project:** paterva/maltego
- **Component:** maltego
- **Retest at:** never
- **Workaround in:** removed, see modules/secops.nix
- **Upstream:** closed-source, no public tracker

Maltego's launcher runs a Java detector that scans hardcoded FHS paths
(`/usr/lib/jvm` and friends). On NixOS none exist, the scan returns null,
and it dies with a NullPointerException in `UnixDetectJava` before the
application starts — despite `JAVA_HOME` already being set correctly.

Workable by creating `/usr/lib/jvm` with a symlink via `systemd.tmpfiles`,
but not worth carrying an FHS shim and an unfree licence for occasional use.
Package removed. SpiderFoot is the open alternative.

---

## lanzaboote: versions below v1.1.0 fail to evaluate

- **Status:** fixed-upstream
- **Project:** nix-community/lanzaboote
- **Component:** lanzaboote
- **Retest at:** n/a
- **Workaround in:** flake.nix (pinned to v1.1.0)
- **Upstream:** fixed in v1.1.0

Releases up to and including v1.0.0 set `boot.bootspec.enable`, which
nixpkgs removed because bootspec is now always generated. The assertion
fails and the whole configuration refuses to evaluate.

Nothing to do but stay on v1.1.0 or later. Recorded because the error
message points at nixpkgs rather than at the flake input, which cost an hour.
