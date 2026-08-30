# TEMPLATE-WINE-AppImage 🍷🐧

> **One-template-fits-all** for packaging Windows applications as portable Linux AppImages using Wine.

Fork this repository to package any Windows `.exe` as a portable AppImage. The consumer AppImage is thin: Wine comes from a shared [pkgforge-dev/wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage) at runtime. Built on [sharun](https://github.com/VHSgunzo/sharun)/[quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages) with hooks for prefix isolation, runtime install, winetricks, and XDG AppData redirection.

**Key features:**
- 🍷 **Shared Wine runtime** — same thin-consumer pattern as [TEMPLATE-ANDROID-AppImage](https://github.com/pkgforge-dev/TEMPLATE-ANDROID-AppImage): find/cache/download [pkgforge-dev/wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage) once; **no Wine bundled** in the consumer
- 📦 **Three payload strategies** — build-time extraction, runtime install, or bundled offline installer
- 🔒 **Per-app isolation** — prefix, payload, and AppData under `$XDG_DATA_HOME/wine-appimage/{apps,data}/$APPNAME`
- 🧰 **Shared tools** — `wine`, `winetricks`, `7z`, `unzip`, `cabextract`, … via wrappers in `wine-appimage/bin/`
- ⚡ **Smart first-run** — winetricks once, hard-copy then symlink sync on version change, AppData redirect
- 🛠️ **CI-ready** — GitHub Actions workflow; no Wine packaged in the consumer AppImage

---

## Table of Contents

- [Quick Start](#quick-start)
- [Repository Layout](#repository-layout)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
  - [Steady-state launch cost](#steady-state-launch-cost)
- [Payload Strategies](#payload-strategies)
  - [Build-Time Extraction (Default)](#build-time-extraction-default)
  - [Runtime Install](#runtime-install)
  - [Bundled Offline Installer](#bundled-offline-installer)
- [App Data & Prefix Locations](#app-data--prefix-locations)
- [Winetricks Verbs](#winetricks-verbs)
- [Desktop Integration](#desktop-integration)
- [Debugging & Troubleshooting](#debugging--troubleshooting)
- [Advanced Topics](#advanced-topics)

---

## Quick Start

1. **Use this template** to create a new repository.
2. **Edit `make-appimage.sh`** — set `APPNAME`, `VERSION`, and `MAIN_EXE` at the top.
3. **Choose a payload strategy** (see below) — uncomment one of the examples in `make-appimage.sh` or set `INSTALL_URL` + `RUN_EXE`.
4. **Provide assets:**
   - `APPNAME.desktop` — desktop entry template (already provided, edit as needed)
   - `APPNAME.svg` or `APPNAME.png` — application icon
5. **Push** — the included GitHub Actions workflow builds and releases automatically.

> **Tip:** Start with [Build-Time Extraction](#build-time-extraction-default) — it's the simplest and most reliable path.

---

## Repository Layout

| File | Purpose |
|------|---------|
| `make-appimage.sh` | **Main build script.** App config, payload examples, patches hook/launcher, deploys zenity, produces the AppImage (does **not** bundle Wine). |
| `get-dependencies.sh` | **CI dependency installer.** `7zip`, `unzip`, `zenity-rs-bin` — no Wine in CI. |
| `AppDir/bin/00-get-wine-appimage.hook` | **Shared Wine resolver.** Finds/downloads wine-AppImage, writes `.target`, installs tool wrappers under `$DATADIR/wine-appimage/bin/`. Do not remove. |
| `APPNAME.hook` | **Runtime hook template.** Prefix init, winetricks, runtime install, AppData redirect, path translation, desktop install/remove. |
| `APPNAME` | **Thin launcher.** Finds the `.exe` and `exec $WINELOADER …`. |
| `APPNAME.desktop` | **Desktop entry template.** Patched with name, version, categories, etc. |
| `.github/workflows/` | **GitHub Actions CI.** Build + release with zsync. |

---

## Configuration

All user-facing settings are at the top of `make-appimage.sh`. **Do not hand-edit the patched hook or launcher** — `make-appimage.sh` patches them automatically via `sed`.

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `APPNAME` | Short app identifier. Used for home dir, desktop file, and namespace. | `notepad++` |
| `VERSION` | App version string. | `8.7.1` |
| `MAIN_EXE` | The actual `.exe` filename. Used for `StartupWMClass` and launcher fallback. | `notepad++.exe` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ICON` | Icon filename (`.svg` or `.png`). | `${APPNAME}.svg` |
| `INSTALL_URL` | Runtime install source — URL or local path. See [Payload Strategies](#payload-strategies). | *(empty)* |
| `RUN_EXE` | Windows-style path to installed exe. Required when `INSTALL_URL` is set. | *(empty)* |
| `INSTALL_FLAGS` | Space-separated silent flags for runtime `.exe`/`.msi` installers. Empty → built-in defaults. Archives ignore this. | *(empty)* |
| `TRICKS` | Space-separated [winetricks](https://github.com/Winetricks/winetricks) verbs. | *(empty)* |
| `WINEDLLOVERRIDES` | Wine DLL override string. | `mscoree,mshtml=;winemenubuilder.exe=d` |
| `WINEDEBUG` | Wine debug channel string. | `fixme-all` |
| `WINEPREFIX_SUBDIR` | Prefix directory name under `$DATADIR/wine-appimage/apps/$APPNAME/`. | `.wine` |
| `WINE_APPIMAGE_PATH` | Pin a specific wine-AppImage (env at runtime or document for users). | *(unset — auto-resolve)* |
| `WINEPREFIX_DEDUP` | Share `system32`/`syswow64`/`winsxs`/`resources`/`globalization` (+ Wine Mono trees if installed) via template prefix. | `1` (on) |
| `GENERIC_NAME` | `GenericName=` in desktop file. | `Wine Application` |
| `COMMENT_NAME` | `Comment=` in desktop file. | `Wine-packaged Windows application` |
| `CATEGORIES_NAME` | `Categories=` in desktop file. | `Utility;` |
| `MIMETYPES_NAME` | `MimeType=` in desktop file. | *(empty)* |

### Build Output Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OUTPATH` | Directory where the final AppImage is placed. | `./dist` |
| `ADD_HOOKS` | Additional sharun hooks to include. | `self-updater.hook` |
| `UPINFO` | Zsync update metadata for AppImageUpdate. | Auto-generated from `GITHUB_REPOSITORY` |

> **Important:** `INSTALL_URL` and `RUN_EXE` must be set **together or not at all**. `make-appimage.sh` will fail the build with a clear error if only one is set.

### Version Detection

Instead of hardcoding `VERSION`, you can query it dynamically:

```sh
# From a GitHub release tag
VERSION=$(wget -qO- https://api.github.com/repos/OWNER/REPO/releases/latest | grep -oP '"tag_name": "v\K[^"]+')

# From a remote file
VERSION=$(wget -qO- https://example.com/version.txt | tr -d '\r')

# From the downloaded binary itself (if it supports --version)
VERSION=$(./AppDir/share/$APPNAME/$MAIN_EXE --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+')
```

---

## How It Works

```
┌───────────────────────────────────────────────────────────────┐
│  User runs ./MyApp.AppImage                                   │
│         │                                                     │
│         ▼                                                     │
│  AppRun (generated by sharun)                                 │
│         │                                                     │
│         └──► Sources *.hook files (alphabetical)              │
│                    │                                          │
│                    ├──► 00-get-wine-appimage.hook             │
│                    │       find / cache / download shared     │
│                    │       wine-AppImage → PATH + tool links  │
│                    │                                          │
│                    └──► YOURAPP.hook                          │
│                          │                                    │
│                          ├──► Sets WINE / WINELOADER          │
│                          ├──► Initializes WINEPREFIX          │
│                          ├──► Applies winetricks (once)       │
│                          ├──► Runtime install (if set)        │
│                          ├──► Redirects %APPDATA% to XDG      │
│                          └──► Translates file args            │
│                               │                               │
│                               ▼                               │
│                          Execs YOURAPP (thin launcher)        │
│                               │                               │
│                               ├──► Finds the .exe             │
│                               └──► DISABLE_AUTO_UPDATES=1     │
│                                    exec $WINELOADER …         │
└───────────────────────────────────────────────────────────────┘
```

Wine is **never bundled**. `00-get-wine-appimage.hook` resolves a shared
[pkgforge-dev/wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage)
(env / `.target` cache / `$PATH` / download), writes `$DATADIR/wine-appimage/.target`,
and installs tool wrappers under `$DATADIR/wine-appimage/bin/` (for `PATH` use of
`7z`, `unzip`, etc.).

The app hook sets `WINE` / `WINELOADER` to the **real wine-AppImage path**
(`$WINE_APPIMAGE_PATH`), not the shell wrappers — winetricks uses `file` on
`$WINE` and fails with “Unknown file arch” if those are scripts.

Every invocation of the shared wine AppImage sets `DISABLE_AUTO_UPDATES=1` **only
on that child** (tool subcommands, thin launcher, `wineboot`, runtime installer,
`winepath`, winetricks). The consumer AppImage’s own self-updater is unaffected.

### What the Hook Handles Automatically

The hook (`APPNAME.hook`) solves several non-obvious Wine-in-AppImage problems:

- **`set -e` safety** — guards `cp`/`find` with `|| true` so empty directories don't abort launch under AppRun's `set -e`
- **Broken symlink cleanup** — removes stale symlinks (`find -L … -maxdepth 1 -type l -delete`) from previous AppImage mounts before `cp -urs`
- **Version-synced data copy** — only when app version changes (tracked via `$_APP_HOME/.synced-version`); first sync is hard `cp -r`, later syncs use `cp -urs`
- **File paths with spaces** — uses shift-and-count loop instead of `eval set --` which would split `"My Music/track.mp3"` into two arguments
- **Fast path translation** — absolute host paths (including mounted drives under `/media`, `/mnt`, etc.) map to `Z:\\…` in shell (Wine’s default `Z:` → `/`); no wine-AppImage spawn per file. Relative paths still use `winepath`
- **Registry backslash escaping** — doubles backslashes for `REGEDIT4` format (`winepath -w` outputs single backslashes; regedit requires `\\`)
- **Placeholder/sed safety** — no runtime "was this patched?" checks. `make-appimage.sh` patches every placeholder unconditionally (with either a real value or empty string), so comparing a variable against its own placeholder text at runtime never happens.
- **Wine tool interception** — `regedit`, `winecfg`, `winetricks`, … passed as `$1` are dispatched as `DISABLE_AUTO_UPDATES=1 $WINE_APPIMAGE_PATH <tool> …`. For `winetricks`, `WINE`/`WINELOADER` are cleared so it uses the ELF binaries inside the wine-AppImage mount (not outer shell wrappers).
- **First-run hard copy** — initial data sync uses `cp -r` so files survive AppImage unmount; later version bumps use `cp -urs` with broken-symlink cleanup
- **Installer flags** — `INSTALL_FLAGS` from `make-appimage.sh` overrides silent args for runtime `.exe`/`.msi` installs (archives ignore it)
- **AppData via symlink** — each profile’s `AppData` is linked into `wine-appimage/data/$APPNAME/AppData` every launch (one-time copy from an existing prefix `AppData` tree if present)

---

### Steady-state launch cost

After first run (prefix + tricks + install done), a normal start should avoid:

| Work | Mitigation |
|------|------------|
| Rewriting `wine-appimage/bin` tools | Skip when `.target` + links already valid |
| `winepath` for absolute file args | Shell `Z:\\` mapping (covers `/media`, `/mnt`, …) |
| Re-downloading the same installer URL | Reuse non-empty file in `$CACHEDIR` |
| Winetricks / wineboot | Gated by `.tricks-applied` / `system.reg` |
| Full per-app `system32` copy | Dedup symlinks after wineboot (`.deduped`) |

Relative file args still call `winepath` (one wine-AppImage start). Meta-verbs like `corefonts` remain slow on **first** run even with a warm download cache (per-font Wine registration).

---

## Payload Strategies

### Build-Time Extraction (Default)

Download and extract the app **during CI**, then bake it into `AppDir/share/$APPNAME`. The hook hard-copies this into the user's `~/.local/share/wine-appimage/apps/$APPNAME/` on first run.

**Best for:** Apps whose license permits redistribution of an extracted copy.

```sh
# Example A: Portable zip (e.g. Notepad++)
mkdir -p "AppDir/share/$APPNAME"
wget -q "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v${VERSION}/npp.${VERSION}.portable.x64.zip" -O app.zip
unzip -q app.zip -d "AppDir/share/$APPNAME"

# Example B: NSIS/Inno installer, extracted with 7z (e.g. foobar2000)
mkdir -p "AppDir/share/$APPNAME"
wget -q "https://www.foobar2000.org/files/foobar2000-${VERSION}.exe" -O installer.exe
7z x -aos installer.exe -o"AppDir/share/$APPNAME" >/dev/null 2>&1
rm -f installer.exe
# mv "AppDir/share/$APPNAME/some-installed-name.exe" "AppDir/share/$APPNAME/$MAIN_EXE"

# Example C: MSI installer
mkdir -p "AppDir/share/$APPNAME"
wget -q "https://example.com/download/${APPNAME}-${VERSION}.msi" -O app.msi
7z x -aos app.msi -o"AppDir/share/$APPNAME" >/dev/null 2>&1
rm -f app.msi
```

> **Note:** Unpacking installers with `7z` avoids running Wine during build, keeping the AppImage self-contained and headless-CI-friendly.

---

### Runtime Install

Download and install the app **on the user's machine** on first launch. The app is not redistributed inside the AppImage — only the installer/zip is downloaded from a URL.

**Best for:** Apps whose license **does not** permit redistribution.

Set in `make-appimage.sh`:

```sh
INSTALL_URL="https://example.com/download/MyApp-${VERSION}-Setup.exe"
RUN_EXE="C:\Program Files\MyApp\MyApp.exe"
# Optional — override silent flags (space-separated). Leave empty for defaults.
# INSTALL_FLAGS="/SILENT /NORESTART"    # Inno Setup example
# INSTALL_FLAGS="/S"                    # NSIS example
# INSTALL_FLAGS="/quiet /norestart"     # MSI example
```

The hook's `_app_install_payload()` auto-detects the format and handles it:

| Format | Action |
|--------|--------|
| `.zip` | Unzipped to `$WINEPREFIX/drive_c/$APPNAME` via `unzip` |
| `.tar.xz` / `.txz` | Extracted with `tar -xJf` |
| `.tar.gz` / `.tgz` | Extracted with `tar -xzf` |
| `.7z` | Extracted with `7z` |
| `.exe` | Run with `INSTALL_FLAGS` (default: `/S /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`) |
| `.msi` | `msiexec /i …` with `INSTALL_FLAGS` (default: `/qn /norestart`) |

The install repeats automatically when:
- The target `RUN_EXE` is missing, **or**
- `_APP_VER` changed since the last install (version marker in `$_APP_HOME/.installed_version`)

HTTP(S) installers are downloaded to `$CACHEDIR` and **reused** if the file is already present and non-empty (version bumps should use a new URL/basename).

After install, Windows `.lnk` shortcuts on the desktop are automatically cleaned up.

---

### Bundled Offline Installer

Ship the raw installer/zip **inside the AppImage** (in `AppDir/share/`) so no network is needed at runtime, but defer actual extraction/installation until first launch.

**Best for:** No stable download URL, or you want to pin an exact binary version.

```sh
# In make-appimage.sh — download during CI
mkdir -p "AppDir/share"
wget -q "https://example.com/download/MyApp-Setup.exe" -O "AppDir/share/MyApp-Setup.exe"

# Then set
INSTALL_URL="$APPDIR/share/MyApp-Setup.exe"
RUN_EXE="C:\Program Files\MyApp\MyApp.exe"
```

Everything else works identically to Runtime Install — format detection, silent flags, version tracking (`.installed_version`), and `.lnk` cleanup all apply. The bundled file is never deleted (it lives in the read-only AppImage mount).

---

## App Data & Prefix Locations

Everything for the shared Wine runtime and consumer apps lives under `$XDG_DATA_HOME/wine-appimage/` (typically `~/.local/share/wine-appimage/`):

```text
$XDG_DATA_HOME/wine-appimage/
├── .template-prefix/            # shared system32/syswow64/winsxs (dedup)
├── .target                      # cached path to the resolved wine-*.AppImage
├── wine-*-anylinux-*.AppImage   # downloaded shared runtime (optional location)
├── bin/                         # tool wrappers → wine, winetricks, 7z, unzip, …
│   ├── .run
│   ├── wine -> .run
│   ├── 7z -> .run
│   └── …
├── apps/$APPNAME/               # per-app home (synced payload + prefix)
│   ├── .wine/                   # WINEPREFIX
│   ├── .synced-version
│   └── …                        # hard-copied / symlinked app files
└── data/$APPNAME/               # %USERPROFILE% / AppData redirect target
    └── AppData/
        ├── Roaming/             # %APPDATA%
        └── Local/               # %LOCALAPPDATA%
```

| Location | Contents | Path |
|----------|----------|------|
| **Tools** | Wrappers for wine, winetricks, 7z, unzip, cabextract, … | `$XDG_DATA_HOME/wine-appimage/bin/` |
| **App home** | Synced payload, `.synced-version` | `$XDG_DATA_HOME/wine-appimage/apps/$APPNAME/` |
| **Wine prefix** | Registry, system DLLs, `drive_c` | `$XDG_DATA_HOME/wine-appimage/apps/$APPNAME/.wine` |
| **App user data** | Settings, saves via AppData redirect | `$XDG_DATA_HOME/wine-appimage/data/$APPNAME/` |
| **Template prefix** | Shared `system32` / `syswow64` / `winsxs` for dedup | `$XDG_DATA_HOME/wine-appimage/.template-prefix/.wine` |

### AppData Redirect (enabled by default)

Every launch (idempotent), the hook ensures each Wine profile’s `AppData`
directory is a **symlink** into the XDG tree:

- `$WINEPREFIX/drive_c/users/<user>/AppData` → `$XDG_DATA_HOME/wine-appimage/data/$APPNAME/AppData`
- `%APPDATA%` → `…/AppData/Roaming`
- `%LOCALAPPDATA%` → `…/AppData/Local`

If the prefix already has a real `AppData` directory, it is copied once into
the XDG tree (stamp: `…/data/$APPNAME/.migrated-from-prefix`) and then replaced
with the symlink. Empty `data/$APPNAME/AppData/{Roaming,Local}` dirs mean the
redirect target exists but the app has not written there yet.

**To disable:** set `REDIRECT_APPDATA=0` (env or in the hook).

> **Caution:** Some older installers hardcode `drive_c` paths. Disable if installation breaks.

---

### Prefix deduplication (enabled by default)

After `wineboot --init`, large **static** Wine trees are replaced with symlinks
into a shared template prefix:

| Shared (symlink → template) | Kept local per app |
|-----------------------------|--------------------|
| `drive_c/windows/system32` | `Fonts`, `temp`, `inf`, … |
| `drive_c/windows/syswow64` | `user.reg`, `system.reg` |
| `drive_c/windows/winsxs` | `drive_c/users/`, Program Files, app dirs |
| `drive_c/windows/resources` | themes / aero, etc. |
| `drive_c/windows/globalization` | sorting / NLS data |
| `mono`, `Microsoft.NET`, `assembly` (if present) | — only when Mono was installed into the template |

**Order:** ensure template → app `wineboot` → replace the three dirs with symlinks.

- Template dir keeps **only** those three trees (everything else from template `wineboot` is deleted)
- Template path: `$XDG_DATA_HOME/wine-appimage/.template-prefix/.wine`
- Per-app stamp: `$WINEPREFIX/.deduped` (skip work on later launches)
- Fast path when template stamp matches current `WINE_APPIMAGE_PATH`
- Typical savings: **~300–500 MB per app** after the first prefix
- Disable: `WINEPREFIX_DEDUP=0` in `make-appimage.sh` or env (default **on**)

Template `wineboot` uses the app’s `WINEDLLOVERRIDES` (`mscoree=` Mono, `mshtml=` Gecko, `winemenubuilder.exe=d` by default — change in `make-appimage.sh`). Template init still appends `winemenubuilder.exe=d` if missing. If Mono is allowed (`mscoree` not disabled) and installed, `mono` / `Microsoft.NET` / `assembly` are kept in the template and shared.

> **Note:** Writes into linked dirs (e.g. some winetricks that drop DLLs into `system32`) affect the **shared** template. Fonts and user data stay private.

---

## Winetricks Verbs

Some apps need .NET, VC++ runtimes, fonts, or DXVK to function. Set `TRICKS` in `make-appimage.sh`:

```sh
TRICKS="dotnet48 vcrun2019 corefonts dxvk"
```

- Runs **once**, right after a fresh `WINEPREFIX` is created
- Tracked via `$WINEPREFIX/.tricks-applied` — won't repeat unless the prefix is wiped
- `winetricks` is the copy inside the shared wine-AppImage (`./MyApp.AppImage winetricks …` or first-run `TRICKS`); only marked applied if every verb succeeds
- Do not point `WINE` at the `wine-appimage/bin/` shell wrappers — winetricks will report “Unknown file arch”
- Uses `--unattended` (not `--force`) so already-installed verbs and cached downloads are skipped on retry
- One `wineserver -k` before and after the whole `TRICKS` batch (not per verb) to avoid extra wine-AppImage startups

**Note on `corefonts`:** a warm download cache only skips HTTP. Each font still needs `cabextract` + Wine registration into the prefix, so first-run can take a while even when files are already under `~/.cache/.../winetricks/corefonts/`.

Common verbs:
- `dotnet48` — .NET Framework 4.8
- `vcrun2019` — Visual C++ 2019 redistributable
- `corefonts` — Microsoft core fonts
- `dxvk` — Vulkan-based D3D9/10/11 implementation
- `fontsmooth=rgb` — Subpixel font smoothing

---

## Desktop Integration

The hook provides `install` and `remove` subcommands:

```bash
./MyApp.AppImage install    # Creates desktop entry + icon
./MyApp.AppImage remove     # Removes desktop entry + icon
```

The desktop file is copied from the AppImage's own `AppDir/$APPNAME.desktop` (already patched by `make-appimage.sh`) to:
- `$XDG_DATA_HOME/applications/$APPNAME.desktop`
- Icon copied to `$XDG_DATA_HOME/icons/hicolor/256x256/apps/` (or `scalable/apps/` for SVG)


### Custom Desktop Actions

Edit the `_app_install()` function in `APPNAME.hook` to add `Actions=` entries (e.g. play/pause, preferences). Follow the [Desktop Entry spec](https://specifications.freedesktop.org/desktop-entry-spec/latest/) format:

```ini
Actions=PlayPause;Preferences;

[Desktop Action PlayPause]
Name=Play/Pause
Exec=$APPIMAGE --playpause

[Desktop Action Preferences]
Name=Preferences
Exec=$APPIMAGE --preferences
```

Then handle those flags in the thin launcher (`APPNAME`) `case` block.

---

## Debugging & Troubleshooting

### Enable Debug Output

```bash
APPRUN_DEBUG=1 ./MyApp.AppImage
```

This enables:
- Full `set -x` trace from AppRun
- Wine/tool errors on stderr (normally silenced to fd 3 → `/dev/null`)
- Hook diagnostic output

The hook uses fd 3 for this: when `APPRUN_DEBUG=1`, `exec 3>&2` duplicates stderr; otherwise `exec 3>/dev/null`. Every command that would normally use `2>/dev/null` instead uses `2>&3`.

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Shared wine not found / download refused | Denied get-hook prompt, empty `.target`, nothing on `PATH` | Install [wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage), set `WINE_APPIMAGE_PATH`, or put it on `PATH`; remove `$CACHEDIR/.no-wine-appimage-*` if you previously declined |
| Wine Mono / Gecko dialog during resolve | Ambiguous PATH entry probed without overrides | Already handled — probe uses `WINEDLLOVERRIDES=mscoree,mshtml=` |
| Update prompts from **wine** AppImage every launch | Older shared copy + self-updater | Already handled — `DISABLE_AUTO_UPDATES=1` on every wine-AppImage child (`exec`, installer, wineboot, winepath, winetricks, `bin/.run`) |
| Consumer AppImage never checks for updates | `DISABLE_AUTO_UPDATES` exported in the consumer process | Do not export it globally |
| Runtime installer fails / no GUI | Wrong silent flags, or app too old for current Wine | Set `INSTALL_FLAGS` (e.g. `/S` or `/PERFORMINSTALL`); prefer 7z extract for legacy installers |
| `Unknown file arch` of `…/wine-appimage/bin/wine` | `WINE` pointed at shell wrappers; winetricks runs `file` on them | Already handled — hook sets `WINE`/`WINELOADER` to `$WINE_APPIMAGE_PATH`; winetricks clears them |
| `"unrecognized registry sequence"` in regedit | Single backslashes in `.reg` file | Already handled — hook doubles backslashes |
| App opens but can't find its files | `cp -urs` symlinks broken after unmount | Already handled — first run hard `cp -r`, later `cp -urs` + broken-link cleanup |
| File argument with spaces splits into two | `eval set --` word-splitting | Already handled — shift-and-count in hook |
| `INSTALL_URL` set but app won't launch | Forgot `RUN_EXE` | `make-appimage.sh` fails the build with a clear error |
| Winetricks verb fails silently | Network issue or verb name typo | Run with `APPRUN_DEBUG=1`; `.tricks-applied` is only written if every verb succeeds |
| AppData not where expected | Redirect disabled or failed | Check `REDIRECT_APPDATA`; data lives under `wine-appimage/data/$APPNAME` |

---

## Advanced Topics

### Shared Wine AppImage (required)

This template **does not bundle Wine**. At runtime, `AppDir/bin/00-get-wine-appimage.hook` finds or downloads [pkgforge-dev/wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage) (~140MB once, shared across all apps from this template).

```bash
# Optional: pin a specific shared Wine AppImage
export WINE_APPIMAGE_PATH="$HOME/Applications/wine-11.15-1-anylinux-x86_64.AppImage"
```

**Resolution order (in `00-get-wine-appimage.hook`):**
1. `WINE_APPIMAGE_PATH` if set and executable
2. `$DATADIR/wine-appimage/.target` (single path cache; must still exist and be executable)
3. Scan `$PATH` for `wine`, `wine.AppImage`, or `wine*anylinux*.AppImage`
4. Prompt to download the latest anylinux release into `$DATADIR/wine-appimage/` (deny is remembered in `$CACHEDIR/.no-wine-appimage-*`)

**Ambiguous PATH names** (not matching `*anylinux*`) are probed with
`… --wine-appimage` under a temporary `WINEPREFIX`, with:
- `DISABLE_AUTO_UPDATES=1` — skip wine-AppImage self-updater during probe
- Default `WINEDLLOVERRIDES` — `mscoree=` Mono, `mshtml=` Gecko, `winemenubuilder.exe=d` (editable in `make-appimage.sh`)
- `WINEDEBUG=-all`

Files already named `*anylinux*.AppImage` are accepted by name only (no probe).

**On success:**
- `$DATADIR/wine-appimage/.target` stores the resolved AppImage path
- Tool wrappers under `$DATADIR/wine-appimage/bin/` for **PATH** convenience (`7z`, `unzip`, `cabextract`, optional `wine` CLI):
  - **Skipped entirely** when `.target` is unchanged and `.run` + key links already exist
  - `.run` is written only if missing
  - tool names → symlinks to `.run` (idempotent)
  - `.run` sets `DISABLE_AUTO_UPDATES=1` only for the wine-AppImage **child**
- `$DATADIR/wine-appimage/bin` is prepended to `PATH`
- The app hook still sets `WINE`/`WINELOADER` to `$WINE_APPIMAGE_PATH` (the real AppImage), not the wrappers

**Cache nesting prevention:** The app hook exports `WINE_HOST_XDG_CACHE_HOME` and resets `XDG_CACHE_HOME` to the host value so the shared Wine AppImage’s AppRun.lib does not nest AppImage-Cache directories.

### Wine Tool Subcommands

You can invoke Wine tools directly through the AppImage:

```bash
./MyApp.AppImage regedit file.reg
./MyApp.AppImage winecfg
./MyApp.AppImage winetricks list-installed
./MyApp.AppImage winepath -w /home/user/file.txt
./MyApp.AppImage msiexec /i package.msi
./MyApp.AppImage notepad
./MyApp.AppImage wineserver -w
```

These are intercepted by the hook and run as
`DISABLE_AUTO_UPDATES=1 $WINE_APPIMAGE_PATH <tool> …`.

`winetricks` additionally clears `WINE`/`WINELOADER` so it discovers the real
ELF `wine`/`wineserver` on the wine-AppImage mount `PATH` (avoids “Unknown file arch”).

### Customizing the Launcher

The thin launcher (`APPNAME`) is for app-specific CLI flags. Add `case` branches for commands that need special handling before reaching the default `exec "$WINELOADER" "$progBinPath" "$@"`:

```sh
case "$1" in
    --playpause)
        DISABLE_AUTO_UPDATES=1 exec "$WINELOADER" "$progBinPath" /playpause
        ;;
    --add)
        shift
        DISABLE_AUTO_UPDATES=1 exec "$WINELOADER" "$progBinPath" /add "$@"
        ;;
esac
```

### Launcher Search Order

When `INSTALL_URL` and `RUN_EXE` are not set, the launcher searches for `MAIN_EXE` in this order:

1. `$DATADIR/wine-appimage/apps/$APPNAME/$MAIN_EXE` — flat layout (foobar2000/Notepad++ style build-time extraction)
2. `$DATADIR/wine-appimage/apps/$APPNAME/.wine/drive_c/Program Files/*/$MAIN_EXE` — 64-bit installer default
3. `$DATADIR/wine-appimage/apps/$APPNAME/.wine/drive_c/Program Files (x86)/*/$MAIN_EXE` — 32-bit installer default
4. `$DATADIR/wine-appimage/apps/$APPNAME/.wine/drive_c/$APPNAME/$MAIN_EXE` — zip/tar/7z runtime-install target

If none are found, it falls back to location 1 for a clear error message.

When `INSTALL_URL` and `RUN_EXE` **are** set, `RUN_EXE` takes priority and is passed directly to Wine.

### Per-App Prefix vs Shared Prefix

**Keep the default per-app prefix.** A shared `$HOME/.wine` across multiple AppImages reintroduces cross-app registry/DLL contamination and makes uninstallation unsafe. The disk savings are small compared to debugging cost. If you genuinely need shared state (e.g. a suite of related apps), override `WINEPREFIX` at runtime:

```bash
WINEPREFIX="$HOME/.shared-wine-suite" ./MyApp.AppImage
```

### Build-Time Layout

This template does **not** deploy Wine into the AppDir. `make-appimage.sh`:

- Copies `APPNAME.hook`, thin launcher, and desktop/icon into `AppDir`
- Keeps `AppDir/bin/00-get-wine-appimage.hook` (do not remove it)
- Deploys `zenity` for notify/prompts in the get-hook
- Sets `ANYLINUX_LIB=0` (no anylinux.so — Wine is not in this AppDir)
- Runs `quick-sharun --make-appimage`

Wine, winetricks, codecs, and related libs come from the shared
[wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage) at runtime.

### CI Dependencies

`get-dependencies.sh` runs in GitHub Actions and installs:

- **Arch Linux packages** — `7zip`, `unzip` (payload extraction at build or runtime)
- **AUR packages** — `zenity-rs-bin` via `make-aur-package` (for notify in the get-hook)

No Wine/GStreamer/SDL packages are installed in CI; the built AppImage is thin
and relies on a shared wine-AppImage on the user’s system (or a download on
first run).

---

## Credits & Links

- **Base Wine deployment:** [pkgforge-dev/wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage)
- **Packaging inspiration:** [foobar2000 AppImage](https://github.com/mmtrt/foobar2000_AppImage), [Notepad++ AppImage](https://github.com/mmtrt/notepad-plus-plus_AppImage)
- **Runtime install flow:** Adapted from [snapcrafters/sommelier-core](https://github.com/mmtrt/sommelier-core)
- **Build system:** [sharun](https://github.com/VHSgunzo/sharun) / [quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages)
- **Issue tracking:** [Anylinux-AppImages#379](https://github.com/pkgforge-dev/Anylinux-AppImages/issues/379)

---

## License

This template is provided as-is for packaging your own applications. Respect the licenses of the Windows applications you package.
