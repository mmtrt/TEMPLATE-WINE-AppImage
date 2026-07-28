# TEMPLATE-WINE-AppImage 🍷🐧

> **One-template-fits-all** for packaging Windows applications as portable Linux AppImages using Wine.

Fork this repository to package any Windows `.exe` as a self-contained, portable AppImage. Built on [sharun](https://github.com/VHSgunzo/sharun)/[quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages) with a reusable hook/launcher pattern that handles Wine prefix isolation, runtime installation, winetricks, and XDG data redirection automatically.

**Key features:**
- 🍷 **Wine bundled** — works out of the box, no system Wine required
- 📦 **Three payload strategies** — build-time extraction, runtime install, or bundled offline installer
- 🔒 **Per-app isolation** — each app gets its own Wine prefix and XDG-compliant data directory
- 🔄 **Shared Wine support** — optionally use a shared [pkgforge-dev/wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage) to save disk space across multiple apps
- ⚡ **Smart first-run** — installs winetricks verbs once, syncs app data only when version changes
- 🛠️ **CI-ready** — includes GitHub Actions workflow for automatic builds and releases

---

## Table of Contents

- [Quick Start](#quick-start)
- [Repository Layout](#repository-layout)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
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
| `make-appimage.sh` | **Main build script.** Set all app-specific configuration here. Downloads, extracts, bundles Wine, patches hook/launcher, and produces the AppImage. |
| `get-dependencies.sh` | **CI dependency installer.** Runs in GitHub Actions to install Arch packages, downloads shared Wine AppImage if enabled, and builds AUR packages. |
| `APPNAME.hook` | **Runtime hook template.** Sourced by AppRun on every launch. Handles Wine env setup, prefix initialization, winetricks, runtime install, file-path translation, and desktop integration. Copied to `AppDir/bin/YOURAPP.hook` during build. |
| `APPNAME` | **Thin launcher template.** Exec'd by AppRun after the hook. Finds the actual `.exe` and launches it via Wine. Copied to `AppDir/bin/YOURAPP` during build. |
| `APPNAME.desktop` | **Desktop entry template.** Gets patched with app name, version, categories, etc. |
| `.github/workflows/` | **GitHub Actions CI.** Builds the AppImage on push/tag and publishes releases with zsync update support. |

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
| `TRICKS` | Space-separated [winetricks](https://github.com/Winetricks/winetricks) verbs. | *(empty)* |
| `WINEDLLOVERRIDES` | Wine DLL override string. | `mscoree,mshtml=` |
| `WINEDEBUG` | Wine debug channel string. | `fixme-all` |
| `WINEPREFIX_SUBDIR` | Prefix directory name under `$DATADIR/anylinux-wine/$APPNAME/`. | `.wine` |
| `USE_SHARED_WINE_APPIMAGE` | Prefer shared `wine-AppImage` if found at runtime. | `0` |
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
│                    └──► YOURAPP.hook                          │
│                          │                                    │
│                          ├──► Sets up WINE env vars           │
│                          ├──► Detects shared wine-AppImage?   │
│                          │       ├─ Yes → shared.AppImage     │
│                          │       └─ No  → bundled wine        │
│                          ├──► Sources random-linker.src.hook  │
│                          │         (copies ld-linux.so)       │
│                          │         [only when bundled]        │
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
│                               └──► exec $WINELOADER           │
│                                    "$progBinPath" "$@"        │
└───────────────────────────────────────────────────────────────┘
```

**Shared Wine path:** When `USE_SHARED_WINE_APPIMAGE=1` resolves to a shared
`wine-AppImage`, `WINE` / `WINESERVER` / `WINELOADER` all point at that external
AppImage. Wine tool subcommands (e.g. `./MyApp.AppImage regedit`) are dispatched
as arguments to the shared AppImage (`wine.AppImage regedit …`), which has its
own internal AppRun that routes to the actual tool. The bundled
`AppDir/bin/wine` and `random-linker.src.hook` are bypassed entirely.

**Bundled Wine path:** When no shared AppImage is found (or
`USE_SHARED_WINE_APPIMAGE=0`), the bundled `AppDir/bin/wine` is used. The
`random-linker.src.hook` copies the patched `ld-linux.so` into `/tmp` so the
patchelf'd wine binary can find its interpreter.

### What the Hook Handles Automatically

The hook (`APPNAME.hook`) solves several non-obvious Wine-in-AppImage problems:

- **`set -e` safety** — guards `cp`/`find` with `|| true` so empty directories don't abort launch under AppRun's `set -e`
- **Broken symlink cleanup** — removes stale symlinks (`find -L … -maxdepth 2 -type l -delete`) from previous AppImage mounts before `cp -urs`
- **Version-synced data copy** — only `cp -urs` when the bundled version actually changed (tracked via `$_APP_HOME/.synced-version`)
- **File paths with spaces** — uses shift-and-count loop instead of `eval set --` which would split `"My Music/track.mp3"` into two arguments
- **Registry backslash escaping** — doubles backslashes for `REGEDIT4` format (`winepath -w` outputs single backslashes; regedit requires `\\`)
- **Placeholder/sed safety** — no runtime "was this patched?" checks. `make-appimage.sh` patches every placeholder unconditionally (with either a real value or empty string), so comparing a variable against its own placeholder text at runtime never happens.
- **Wine tool interception** — `regedit`, `winecfg`, `wineconsole`, `winetricks`, `winefile`, `wineboot`, `wineserver`, `winepath`, `msiexec`, `notepad` passed as `$1` are intercepted and dispatched correctly whether using bundled or shared Wine. `WINESERVER` resolves to the actual `wineserver` binary for bundled wine, or to the shared AppImage (which dispatches subcommands internally) for shared wine.
- **Random linker hook ordering safety** — sources `random-linker.src.hook` inline before `wineboot --init` to avoid "could not open /tmp/.XXXXXXXXXX" errors when hook filename sorts before the random-linker hook alphabetically

---

## Payload Strategies

### Build-Time Extraction (Default)

Download and extract the app **during CI**, then bake it into `AppDir/share/$APPNAME`. The hook hard-copies this into the user's `~/.local/share/anylinux-wine/$APPNAME/` on first run.

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
```

The hook's `_app_install_payload()` auto-detects the format and handles it:

| Format | Action |
|--------|--------|
| `.zip` | Unzipped to `$WINEPREFIX/drive_c/$APPNAME` via `unzip` |
| `.tar.xz` / `.txz` | Extracted with `tar -xJf` |
| `.tar.gz` / `.tgz` | Extracted with `tar -xzf` |
| `.7z` | Extracted with `7z` |
| `.exe` | Run silently: `/S /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |
| `.msi` | Run via `msiexec /i ... /qn /norestart` |

The install repeats automatically when:
- The target `RUN_EXE` is missing, **or**
- `_APP_VER` changed since the last install (version marker in `$_APP_HOME/.installed_version`)

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

Two distinct locations, deliberately separated:

| Location | Contents | Path |
|----------|----------|------|
| **Wine prefix** | Wine registry, system DLLs, `drive_c` | `$XDG_DATA_HOME/anylinux-wine/$APPNAME/.wine` |
| **App user data** | Settings, saves, `%APPDATA%` redirect | `$XDG_DATA_HOME/$APPNAME/AppData/...` |

### Why separate them?

- **Wine prefix** is implementation detail — grouped under `anylinux-wine/` so you can back up or wipe all Wine apps together.
- **App user data** is user-facing — lives where a native Linux port would put it (`~/.local/share/MyApp/`), not buried inside a Wine prefix.

### AppData Redirect (enabled by default)

On first launch, the hook patches the Wine registry to redirect:
- `%USERPROFILE%` → `$XDG_DATA_HOME/$APPNAME`
- `%APPDATA%` → `$XDG_DATA_HOME/$APPNAME/AppData/Roaming`
- `%LOCALAPPDATA%` → `$XDG_DATA_HOME/$APPNAME/AppData/Local`

**To disable:** Set `REDIRECT_APPDATA=0` in `APPNAME.hook`, in the AppData redirect section (search for `REDIRECT_APPDATA="${REDIRECT_APPDATA:-1}"`).

> **Caution:** Some older installers hardcode `drive_c` paths and get confused by the redirect. Disable if your app's installer fails.

---

## Winetricks Verbs

Some apps need .NET, VC++ runtimes, fonts, or DXVK to function. Set `TRICKS` in `make-appimage.sh`:

```sh
TRICKS="dotnet48 vcrun2019 corefonts dxvk"
```

- Runs **once**, right after a fresh `WINEPREFIX` is created
- Tracked via `$WINEPREFIX/.tricks-applied` — won't repeat unless the prefix is wiped
- `winetricks` is fetched from upstream and bundled at build time (unless `REQUIRE_SHARED_WINE_APPIMAGE=1`)
- When using a shared `wine-AppImage`, winetricks is dispatched through it (the shared AppImage bundles its own copy)

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

When `USE_SHARED_WINE_APPIMAGE=1`, an additional fix-icon desktop file (`fix_icon_wine_$APPNAME.desktop`) is created to ensure `StartupWMClass` matching works correctly with shared Wine.

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
| `oops... not enough space for load commands` | `patchelf --add-needed` on Wine binary post-11.8 | Already handled — template patches `libc.so.6` instead of the wine binary |
| `could not open /tmp/.XXXXXXXXXX` | `random-linker.src.hook` hasn't run yet | Already handled — hook sources it inline before `wineboot --init` |
| `"unrecognized registry sequence"` in regedit | Single backslashes in `.reg` file | Already handled — hook doubles backslashes via `sed 's/\\/\\\\/g'` |
| App opens but can't find its files | `cp -urs` symlinks broken after unmount | Already handled — first run uses hard copy (`cp -r` without `-s`), only later syncs use symlinks |
| File argument with spaces splits into two | `eval set --` word-splitting | Already handled — shift-and-count pattern in hook |
| `INSTALL_URL` set but app won't launch | Forgot `RUN_EXE` | `make-appimage.sh` fails build with clear error |
| Winetricks verb fails silently | Network issue or verb name typo | Run with `APPRUN_DEBUG=1` and check output |
| AppData not where expected | Redirect disabled or failed | Check `REDIRECT_APPDATA` and registry via `wine regedit` |
| Shared Wine not found | `WINE_APPIMAGE_PATH` not set and no auto-discovered candidate | Set `WINE_APPIMAGE_PATH` explicitly, or install wine-AppImage to `~/Applications` |

### Testing in CI

`make-appimage.sh` runs:
```bash
APPRUN_DEBUG=1 quick-sharun --test ./dist/*.AppImage
```

If the app has issues running in CI (e.g. requires a GPU or interactive display), use `--simple-test` instead.

---

## Advanced Topics

### Shared Wine AppImage

If you build multiple apps from this template, users can save ~140MB per app by installing [pkgforge-dev/wine-AppImage](https://github.com/pkgforge-dev/wine-AppImage) once:

```bash
# User sets this before running any of your apps
export WINE_APPIMAGE_PATH="$HOME/Applications/wine-11.13-1-anylinux-x86_64.AppImage"
```

Set `USE_SHARED_WINE_APPIMAGE="1"` in `make-appimage.sh` to default this on. The AppImage still bundles its own Wine as fallback.

Set `REQUIRE_SHARED_WINE_APPIMAGE="1"` to **remove the bundled Wine entirely** — AppImage becomes much smaller but hard-requires the shared one. When this is set, `USE_SHARED_WINE_APPIMAGE` is forced on in the hook regardless of its own setting, since there is no bundled fallback.

**Auto-discovery:** Even without `WINE_APPIMAGE_PATH` set, the hook searches common locations (`~/Applications`, `~/.local/bin`, `~/Downloads`, `$XDG_DATA_HOME/soar/bin`, `$HOME`) for `wine-*-anylinux-*.AppImage` and picks the highest version using numeric version sorting (`sort -V`). Priority: plain Arch builds (no channel prefix) > stable > staging > devel > unrecognized.

**Cache nesting prevention:** When using a shared wine-AppImage, the hook exports `WINE_HOST_XDG_CACHE_HOME` and resets `XDG_CACHE_HOME` to the host value. This prevents the shared AppImage's own AppRun.lib from nesting cache directories (AppImage-Cache inside AppImage-Cache) when it rewrites `XDG_CACHE_HOME` again.

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

These are intercepted by the hook's `case "$1" in` block and dispatched correctly:
- **Shared wine.AppImage:** passes subcommand as argument (`wine.AppImage regedit file.reg`)
- **Bundled wine:** execs the separate binary directly (`$APPDIR/bin/regedit`)

### Customizing the Launcher

The thin launcher (`APPNAME`) is for app-specific CLI flags. Add `case` branches for commands that need special handling before reaching the default `exec "$WINELOADER" "$progBinPath" "$@"`:

```sh
case "$1" in
    --playpause)
        exec "$WINELOADER" "$progBinPath" /playpause
        ;;
    --add)
        shift
        exec "$WINELOADER" "$progBinPath" /add "$@"
        ;;
esac
```

### Launcher Search Order

When `INSTALL_URL` and `RUN_EXE` are not set, the launcher searches for `MAIN_EXE` in this order:

1. `$DATADIR/anylinux-wine/$APPNAME/$MAIN_EXE` — flat layout (foobar2000/Notepad++ style build-time extraction)
2. `$DATADIR/anylinux-wine/$APPNAME/.wine/drive_c/Program Files/*/$MAIN_EXE` — 64-bit installer default
3. `$DATADIR/anylinux-wine/$APPNAME/.wine/drive_c/Program Files (x86)/*/$MAIN_EXE` — 32-bit installer default
4. `$DATADIR/anylinux-wine/$APPNAME/.wine/drive_c/$APPNAME/$MAIN_EXE` — zip/tar/7z runtime-install target

If none are found, it falls back to location 1 for a clear error message.

When `INSTALL_URL` and `RUN_EXE` **are** set, `RUN_EXE` takes priority and is passed directly to Wine.

### Per-App Prefix vs Shared Prefix

**Keep the default per-app prefix.** A shared `$HOME/.wine` across multiple AppImages reintroduces cross-app registry/DLL contamination and makes uninstallation unsafe. The disk savings are small compared to debugging cost. If you genuinely need shared state (e.g. a suite of related apps), override `WINEPREFIX` at runtime:

```bash
WINEPREFIX="$HOME/.shared-wine-suite" ./MyApp.AppImage
```

### Build-Time Wine Modifications

When bundling Wine (i.e. `REQUIRE_SHARED_WINE_APPIMAGE=0`), `make-appimage.sh` applies several fixes:

- **Patched linker workaround** — Wine post-11.8 breaks when `patchelf --add-needed` is applied directly to the wine binary. The template instead patches `libc.so.6` to load `anylinux.so`, and uses `random-linker.src.hook` to copy the real dynamic linker into place at runtime.
- **Stripped Windows DLLs** — On `x86_64`, MinGW strip is run on `x86_64-windows/*.dll` and `i386-windows/*.dll` to reduce size.
- **Library path setup** — Adds `AppDir/lib/wine/x86_64-unix` to `LD_LIBRARY_PATH` in `AppDir/.env`.

### CI Dependencies

`get-dependencies.sh` runs in GitHub Actions and handles:

- **Arch Linux packages** — Installs `wine`, `cabextract`, `sdl2`, `pipewire-audio`, `harfbuzz`, GStreamer plugins, `7zip`, `unzip`, and `mingw-w64-binutils` (on x86_64) via `pacman`.
- **Debloated packages** — Uses `get-debloated-pkgs` to install minimal `ffmpeg-mini`.
- **AUR packages** — Builds `zenity-rs-bin` via `make-aur-package`.
- **Shared Wine download** — When `REQUIRE_SHARED_WINE_APPIMAGE=1`, downloads the latest `wine-AppImage` from GitHub releases and sets `WINE_APPIMAGE_PATH` in the CI environment.

When `REQUIRE_SHARED_WINE_APPIMAGE=1`, only `7zip` and `unzip` are installed (no Wine, no GStreamer, no SDL), since the AppImage will use the shared Wine at runtime.

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
