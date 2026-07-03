# TEMPLATE-WINE-AppImage 🍷🐧

Fork this repository to package a Windows application as an AppImage,
using [sharun](https://github.com/VHSgunzo/sharun)/[quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages)
to bundle Wine, and a reusable hook that handles the common pain points of
running Wine apps inside an AppImage.

Built on top of [pkgforge-dev/wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage)
(the base Wine deployment used in `make-appimage.sh`), some changes taken from
packaging [foobar2000](https://github.com/mmtrt/foobar2000_AppImage) and
[Notepad++](https://github.com/mmtrt/notepad-plus-plus_AppImage), with the
optional runtime-install flow adapted from
[snapcrafters/sommelier-core](https://github.com/mmtrt/sommelier-core)
(stripped of all snapd content-interface plumbing — sharun/AppRun already
handles library and Wine-runtime provisioning, so none of that is needed).
Tracks [Anylinux-AppImages#379](https://github.com/pkgforge-dev/Anylinux-AppImages/issues/379).

---

## What this template solves for you

Running an arbitrary `.exe` under Wine, inside an AppImage, hits several
non-obvious problems every time. This template's `APPNAME.hook` +
`APPNAME` launcher already handle:

- **`set -e` aborting first launch** — `AppRun` runs with `set -e`; naive
  `cp`/`find` calls that legitimately return non-zero on an empty directory
  will kill the whole launch unless guarded with `|| true`.
- **Broken app files after first run** — populating `$HOME/.appname` via
  symlinks (`cp -urs`) breaks once the AppImage's temporary mount goes away.
  First run needs a hard copy; only later syncs can safely use symlinks.
- **File paths with spaces** — translating file arguments to Wine paths via
  `eval set --` silently splits `"My Music/track.mp3"` into two arguments.
  Use the shift-and-count pattern in the hook instead.
- **`.reg` file backslash escaping** — `winepath -w` outputs single
  backslashes (`C:\Users\...`), but REGEDIT4 format requires them doubled
  in quoted string values, or `regedit` reports "unrecognized registry
  sequence" and silently ignores the affected line.
- **sed replacement-text escaping** — `sed`'s *replacement* text (not just
  its search pattern) interprets backslashes specially, so patching a
  Windows path like `RUN_EXE` into the hook via `sed` silently eats every
  backslash unless they're doubled first.
- **Placeholder/sed collisions** — comparing a variable against its own
  placeholder text at runtime (`[ "$VAR" = "PLACEHOLDER" ]`) breaks once
  `sed` has already patched that placeholder text everywhere it appears in
  the file, including inside the comparison itself. This template's
  placeholders are patched unconditionally at build time instead, with no
  runtime "was this patched?" self-check.

## Usage

1. **Use this template** to create a new repository.
2. Edit `make-appimage.sh` — every user-facing setting lives at the top of
   this file (see "Configuration reference" below).
3. Rename `APPNAME.hook` and `APPNAME` however you like, or leave them —
   `make-appimage.sh` copies and patches them into `AppDir/bin/` for you.
4. Edit the `_app_install()` function in `APPNAME.hook` if you need
   desktop actions beyond the basic entry (play/pause, config, etc. — see
   foobar2000's media-key commands for the pattern). `MimeType=`,
   `Comment=`, `GenericName=`, `Categories=` are already patched from
   `make-appimage.sh` variables — see below.
5. Add app-specific CLI flag handling to the `APPNAME` launcher's `case`
   block if your app needs it.
6. Provide `APPNAME.desktop` and an icon (`.svg` or `.png` — set `ICON=`
   in `make-appimage.sh` to match).
7. Push — the included GitHub Actions workflow builds and releases
   automatically.

## Configuration reference

Everything below is set once, near the top of `make-appimage.sh`, and
`make-appimage.sh` patches the relevant values into `APPNAME.hook` at
build time via `sed`. You should not need to hand-edit patched values
directly into the hook.

| Variable | Purpose | Default |
|---|---|---|
| `VERSION` | App version string | — (required) |
| `APPNAME` | Short app identifier — desktop file name, home dir name, etc. | — (required) |
| `MAIN_EXE` | The `.exe` filename — used for `StartupWMClass` and the launcher's fallback search regardless of payload strategy | — (required) |
| `ICON` | Icon filename (`.svg` or `.png`) | `${APPNAME}.svg` |
| `INSTALL_URL` | Runtime-install download link or bundled local path — see "Three ways to get your app's payload in" | empty (disabled) |
| `RUN_EXE` | Windows-style path to the installed exe, only used together with `INSTALL_URL` | empty (disabled) |
| `TRICKS` | Space-separated winetricks verbs | empty (disabled) |
| `WINEDLLOVERRIDES` | Wine DLL override string | `mscoree,mshtml=` |
| `WINEDEBUG` | Wine debug channel string | `fixme-all` |
| `WINEPREFIX_SUBDIR` | Prefix directory name under `$DATADIR/anylinux-wine/$APPNAME/` | `.wine` |
| `GENERIC_NAME` / `COMMENT_NAME` / `CATEGORIES_NAME` / `MIMETYPES_NAME` | Patched into `APPNAME.desktop`'s `GenericName=`/`Comment=`/`Categories=`/`MimeType=` | app-specific, fill these in |

`INSTALL_URL`/`RUN_EXE` must be set together or not at all —
`make-appimage.sh` fails the build with a clear error if only one is set,
since one without the other is almost always a mistake.

## Should apps share a single `$HOME/.wine` prefix?

**No — keep the default per-app prefix** (`$DATADIR/anylinux-wine/$APPNAME/.wine`). A
shared prefix across multiple Wine AppImages reintroduces exactly the kind
of cross-app registry/DLL/file-association contamination that per-app
isolation is meant to avoid, and turns "uninstall app A" into an operation
that can silently affect app B. The disk-space savings from sharing a
prefix are real but small compared to the debugging cost of a shared,
mutable Wine environment between unrelated apps. If a specific deployment
genuinely needs shared state (e.g. a suite of related apps), that's what
overriding `WINEPREFIX` directly at runtime is for — it's not something
the template should default to.

## Three ways to get your app's payload in

**Build-time extraction (default, foobar2000/Notepad++ style)** — download
a zip or 7z-extract an installer during `make-appimage.sh`, bake the result
into `AppDir/share/$APPNAME`. The hook's "App home setup" block hard-copies
this into `~/.$APPNAME` on first run. Use this whenever the app's license
permits redistributing an already-installed copy.

**Runtime install (sommelier-core style)** — if the license does *not*
permit redistribution, download and install the app fresh inside the
user's own Wine prefix on first launch, or whenever `_APP_VER` changes.
`_app_install_payload()` in `APPNAME.hook` handles common Windows
distribution formats automatically based on the downloaded file's
extension:

| Format | Handling |
|--------|----------|
| `.zip` | Unpacked directly into `$WINEPREFIX/drive_c/$APPNAME`, no Wine involved |
| `.tar.xz` / `.txz` | Extracted with `tar -xJf` into `$WINEPREFIX/drive_c/$APPNAME` |
| `.tar.gz` / `.tgz` | Extracted with `tar -xzf` into `$WINEPREFIX/drive_c/$APPNAME` |
| `.7z` | Extracted with `7z`/`7zz` (whichever is bundled) into `$WINEPREFIX/drive_c/$APPNAME` |
| `.exe` | Run silently under Wine with `/S /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` (covers NSIS and Inno installers — check `wine installer.exe /?` if a specific installer uses different flags) |
| `.msi` | Run via `msiexec /i ... /qn /norestart` |

Set `INSTALL_URL` and `RUN_EXE` in `make-appimage.sh`. `RUN_EXE` is a
Windows-style path (e.g. `C:\Program Files\MyApp\MyApp.exe`) — write it
with either single or doubled backslashes, and either drive-letter case;
all forms resolve identically. Leave both empty to disable this and fall
back to build-time extraction instead.

The thin launcher (`APPNAME`) prefers `RUN_EXE` when both `INSTALL_URL`
and `RUN_EXE` are set, and otherwise searches, in order:

1. `$DATADIR/anylinux-wine/$APPNAME/$MAIN_EXE` (flat, foobar2000/Notepad++ style)
2. `$DATADIR/anylinux-wine/$APPNAME/.wine/drive_c/Program Files/*/$MAIN_EXE` (64-bit installer default)
3. `$DATADIR/anylinux-wine/$APPNAME/.wine/drive_c/Program Files (x86)/*/$MAIN_EXE` (32-bit installer default)
4. `$DATADIR/anylinux-wine/$APPNAME/.wine/drive_c/$APPNAME/$MAIN_EXE` (zip/tar/7z runtime-install target)

Desktop `.lnk` shortcuts the installer drops (via WineMenuBuilder) are
cleaned up automatically after install, since they don't work in Linux
and just confuse users.

**Bundled payload, installed on first launch (hybrid of the above two)** —
sometimes you want the AppImage to work fully offline (no network needed
at runtime) but still can't pre-extract the app at build time. Ship the
installer/zip inside `AppDir/share/` at build time (see "Example D" in
`make-appimage.sh`) and set `INSTALL_URL` to that local path instead of a
URL:

```sh
INSTALL_URL="$APPDIR/share/MyApp-Setup.exe"
```

Everything else — format detection, silent-install flags, version
tracking, `.lnk` cleanup — works identically to the network-download case;
`_app_install_payload()` just skips the `wget` step and never deletes the
file afterward (it lives in the read-only AppImage mount, not a temp
download).

## Where app files live

Two distinct locations, deliberately kept separate:

- **`$DATADIR/anylinux-wine/$APPNAME/`** — Wine plumbing: the prefix
  (`.wine/`), the copied-in exe (build-time extraction) or install
  target (runtime install). This is implementation detail grouped
  together with every other Wine app under one `anylinux-wine/`
  namespace, so it's easy to find/clean/back up as a set if you have
  several Wine AppImages installed.
- **`$DATADIR/$APPNAME/AppData/...`** — the app's actual user-facing
  data (settings, save files), redirected there from Wine's default
  `%APPDATA%`/`%LOCALAPPDATA%` via the one-time registry patch described
  below. This lives where a *native* Linux port of the app would put its
  data, not nested under the Wine-specific namespace — a user looking
  for "my Notepad++ settings" wouldn't think to check under
  `anylinux-wine/`.

Both replace the older `$HOME/.$APPNAME` dotfile-in-home convention with
proper XDG-compliant locations (`$DATADIR` resolves to `$XDG_DATA_HOME`,
normally `$HOME/.local/share`).

## App data location

By default `APPNAME.hook` redirects `%APPDATA%`/`%LOCALAPPDATA%`/
`%USERPROFILE%` (via a one-time registry patch on first launch) to
`$XDG_DATA_HOME/$APPNAME/AppData/...` instead of leaving them buried
inside `$WINEPREFIX/drive_c/users/...`. This keeps the app's actual
settings/save data somewhere predictable — easy to back up, sync, or wipe
independently of the whole Wine prefix. Set `REDIRECT_APPDATA=0` near the
top of that section in `APPNAME.hook` to disable it if your app's
installer hardcodes `drive_c` paths and gets confused by the redirect
(uncommon, but happens with some older installers).

## Wine environment defaults

`WINEDLLOVERRIDES`, `WINEDEBUG`, and `WINEPREFIX_SUBDIR` are set in
`make-appimage.sh` at their actual default values — change them directly
there if your app needs something different. All three also stay
overridable at runtime via environment variables regardless of what's
baked in at build time (e.g. `WINEDEBUG=+all ./MyApp.AppImage` for a
one-off debug run).

## Winetricks verbs

Some apps need specific Wine components to work at all — .NET, Visual C++
runtimes, DXVK, particular fonts, etc. Set `TRICKS` (space-separated
winetricks verb names) in `make-appimage.sh`:

```sh
TRICKS="dotnet48 vcrun2019 corefonts"
```

These run once, right after a fresh `$WINEPREFIX` is initialized — not on
every launch — tracked via a `.tricks-applied` marker file in the prefix.
`winetricks` itself is fetched from upstream and bundled at build time in
`make-appimage.sh`; remove that step if your app doesn't need `TRICKS`.


## Debugging

Set `APPRUN_DEBUG=1` when running the AppImage (or exported before
`quick-sharun --test` in CI) to see real Wine/tool errors from
`wineboot`, `regedit`, and the runtime-install download/extract steps,
instead of the routine `2>/dev/null` silencing used otherwise. This is the
same variable AppRun's own generated script checks to enable a full
`set -x` command trace, so one flag gives you both.

`make-appimage.sh`'s test step sets this automatically so CI failures are
diagnosable from the workflow log without needing to reproduce locally
first.

## What you should NOT need to change

The Wine path translation (shift-and-count loop at the bottom of
`APPNAME.hook`), the placeholder-patching mechanism, and the launcher's
fallback search order are all app-agnostic — you shouldn't need to touch
any of them unless your app has genuinely unusual requirements (e.g. IPC
to an already-running instance, like foobar2000's `/add` enqueue command
serialized via `flock` — see that repo if you need this pattern).

Do not compare a build-time-patched variable against its own placeholder
text at runtime (e.g. `[ "$FOO" = "FOO_HERE" ]`) — `sed` replaces every
occurrence of the placeholder in the file, including inside that
comparison, which silently breaks the check. `make-appimage.sh` always
patches every placeholder unconditionally (with either a real value or an
empty string), so no runtime "was this patched?" check is ever needed.

---

More at: [AnyLinux-AppImages](https://pkgforge-dev.github.io/Anylinux-AppImages/)
