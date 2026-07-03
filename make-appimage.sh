#!/bin/sh

set -eu

ARCH=$(uname -m)
VERSION=APP_VERSION_HERE # example command to get version of application here
export ARCH VERSION
export OUTPATH=./dist
export ADD_HOOKS="self-updater.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export APPNAME=APPNAME_HERE # change the application name here
# ICON must match whichever icon file you actually provide (.png or .svg) —
# this template ships an APPNAME.svg placeholder; change the extension here
# if you're using a PNG instead.
export ICON="${APPNAME}.svg"
export DESKTOP="${APPNAME}.desktop"
export DEPLOY_SDL=1
export DEPLOY_PIPEWIRE=1
export DEPLOY_GSTREAMER=1
export DEPLOY_VULKAN=1
export DEPLOY_OPENGL=1
# MAIN_EXE is always required — the .exe filename identifying your app.
# Used for StartupWMClass (window matching) regardless of which payload
# strategy you use, and as the launcher's fallback search target when
# RUN_EXE is not set.
export MAIN_EXE=MAIN_EXE_HERE

# Runtime-install flow (optional — see README "Three ways to get your
# app's payload in"). Set INSTALL_URL to a direct download link (.exe,
# .msi, .zip, .tar.xz, .tar.gz, or .7z) or a local path inside AppDir/share
# for a bundled/offline install. RUN_EXE only OVERRIDES where the launcher
# looks for the exe after install — it does not replace MAIN_EXE, which
# must still name the correct .exe filename. Leave both empty/unset to use
# build-time extraction instead (see the App payload examples below) —
# this is the default and simplest path for most apps.
INSTALL_URL=
RUN_EXE=

# Winetricks verbs your app needs to work at all (e.g. .NET, VC++
# runtimes, specific fonts) — space-separated winetricks verb names. Runs
# once on a fresh WINEPREFIX, before the app installs/launches. Leave
# empty if your app doesn't need any. See README "Winetricks verbs".
TRICKS=

# Wine env var defaults, shown here at their actual default values — these
# are what the hook uses out of the box. Change them if your app needs
# something different (e.g. WINEDLLOVERRIDES to disable a misbehaving DLL,
# WINEDEBUG to trace calls during development). Both stay overridable at
# runtime via env regardless of what's set here.
WINEDLLOVERRIDES="mscoree,mshtml="
WINEDEBUG="fixme-all"

# WINEPREFIX defaults to $HOME/.$APPNAME/.wine — change the value below if
# you need a different subdir name (e.g. to match an existing installation's
# layout, or to avoid a clash).
WINEPREFIX_SUBDIR=".wine"

# Only for patching desktop file
GENERIC_NAME="Wine Application" # example: Audio player
COMMENT_NAME="Wine-packaged Windows application" # example: Simple and powerful audio player
CATEGORIES_NAME="Utility;" # example: AudioVideo;Audio;Player;
MIMETYPES_NAME="" # example: audio/aac;audio/x-mp3;

# Pick ONE of the two approaches below (or use RUNTIME INSTALL in the hook
# instead — see README). Both examples use real, working URLs so you can
# see the pattern end-to-end; replace with your own app's download link.

# --- Example A: plain zip / portable build (build-time extraction) --------
# e.g. Notepad++'s portable zip release:
#
# mkdir -p "AppDir/share/$APPNAME"
# wget -q "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.7.1/npp.8.7.1.portable.x64.zip" \
#     -O app.zip
# unzip -q app.zip -d "AppDir/share/$APPNAME"

# --- Example B: installer .exe, extracted at build time --------------------
# Most NSIS/Inno installers can be unpacked with 7z instead of run through
# Wine, which keeps the AppImage self-contained and avoids running the
# installer's UI at all. e.g. foobar2000's installer:
#
# mkdir -p "AppDir/share/$APPNAME"
# wget -q "https://www.foobar2000.org/files/foobar2000-${VERSION}.exe" \
#     -O installer.exe
# 7z x -aos installer.exe -o"AppDir/share/$APPNAME" >/dev/null 2>&1
# rm -f installer.exe
# # Installer exe names often don't match the real Windows binary name —
# # rename here so it matches MAIN_EXE:
# # mv "AppDir/share/$APPNAME/some-installed-name.exe" "AppDir/share/$APPNAME/$MAIN_EXE"

# --- Example C: .msi installer, extracted at build time --------------------
# msiexec-based installers can be extracted directly with 7z too:
#
# mkdir -p "AppDir/share/$APPNAME"
# wget -q "https://example.com/download/${APPNAME}-${VERSION}.msi" -O app.msi
# 7z x -aos app.msi -o"AppDir/share/$APPNAME" >/dev/null 2>&1
# rm -f app.msi

# --- Example D: bundle the installer/zip itself, install on first launch ---
# Instead of extracting at build time, ship the raw installer/zip inside the
# AppImage and let APPNAME.hook's RUNTIME INSTALL flow run it on first
# launch. Keeps the AppImage self-contained (no network needed at runtime)
# while still deferring the actual install — set INSTALL_URL in the hook to
# the bundled path shown below.
#
# Downloaded fresh during CI (no need to store the file in the repo):
#
# mkdir -p "AppDir/share"
# wget -q "https://example.com/download/MyApp-Setup.exe" \
#     -O "AppDir/share/MyApp-Setup.exe"
# # Then in APPNAME.hook: INSTALL_URL="$APPDIR/share/MyApp-Setup.exe"
#
# Committed directly to this repo instead (e.g. no stable download URL, or
# you want to pin an exact binary) — put the file in a top-level payload/
# directory (add it to .gitattributes as `binary` / consider Git LFS if
# it's large), then just copy it in at build time:
#
# mkdir -p "AppDir/share"
# cp "payload/MyApp-Setup.exe" "AppDir/share/MyApp-Setup.exe"
# # Then in APPNAME.hook: INSTALL_URL="$APPDIR/share/MyApp-Setup.exe"

# App hook + thin launcher
# Copy and rename the template hook/launcher for your app, then patch in
# the version and app name. See AppDir/bin/APPNAME.hook and AppDir/bin/APPNAME
# in this template for the reusable pattern (env setup, install/remove,
mkdir -p "AppDir/bin"
cp APPNAME.hook "AppDir/bin/${APPNAME}.hook" && rm APPNAME.hook
cp APPNAME "AppDir/bin/${APPNAME}" && rm APPNAME
cp APPNAME.desktop "${APPNAME}.desktop" && rm APPNAME.desktop
[ -f "APPNAME.svg" ] && cp APPNAME.svg "${APPNAME}.svg" && rm APPNAME.svg
[ -f "APPNAME.png" ] && cp APPNAME.png "${APPNAME}.png" && rm APPNAME.png

# Mark files exec
chmod +x "AppDir/bin/${APPNAME}.hook" "AppDir/bin/${APPNAME}" "${APPNAME}.desktop"

# Sanity check: INSTALL_URL and RUN_EXE only make sense set together — one
# without the other is almost always a mistake (e.g. forgot to set RUN_EXE
# after enabling runtime install, or leftover RUN_EXE from copy-pasting an
# example without INSTALL_URL).
if [ -n "$INSTALL_URL" ] && [ -z "$RUN_EXE" ]; then
        echo "ERROR: INSTALL_URL is set but RUN_EXE is empty — the launcher" >&2
        echo "won't know where the installed app ends up. Set RUN_EXE too." >&2
        exit 1
fi
if [ -z "$INSTALL_URL" ] && [ -n "$RUN_EXE" ]; then
        echo "ERROR: RUN_EXE is set but INSTALL_URL is empty — RUN_EXE has" >&2
        echo "no effect without a runtime install to place the app there." >&2
        exit 1
fi

# Patch hook script
sed -i "s|_APP_VER=|_APP_VER=${VERSION}|" "AppDir/bin/${APPNAME}.hook"
sed -i "s|_APP_NAME=\"APPNAME_HERE\"|_APP_NAME=\"${APPNAME}\"|" "AppDir/bin/${APPNAME}.hook"
sed -i "s|_APP_BIN=\"MAIN_EXE_HERE\"|_APP_BIN=\"${MAIN_EXE}\"|" "AppDir/bin/${APPNAME}.hook"
# INSTALL_URL/RUN_EXE/TRICKS patches always run, substituting either the
# real value or an empty string — never conditionally skipped. Skipping the
# sed when a variable is empty would leave the literal placeholder text
# (e.g. "INSTALL_URL_HERE") in place as the hook's actual runtime value,
# since ${INSTALL_URL:-INSTALL_URL_HERE} only supplies that text as a
# default, it doesn't distinguish "empty on purpose" from "never patched".
#
# sed's REPLACEMENT text (not just its search pattern) interprets
# backslashes specially (\1, \n, etc.), so any literal backslash in
# INSTALL_URL/RUN_EXE — near-guaranteed for RUN_EXE since Windows paths
# use "C:\Program Files\App\App.exe" — gets silently eaten unless doubled
# first. Escape before substituting so the path survives intact.
_install_url_escaped=$(printf '%s' "$INSTALL_URL" | sed 's/\\/\\\\/g')
_run_exe_escaped=$(printf '%s' "$RUN_EXE" | sed 's/\\/\\\\/g')
sed -i "s|INSTALL_URL_HERE|${_install_url_escaped}|" "AppDir/bin/${APPNAME}.hook"
sed -i "s|RUN_EXE_HERE|${_run_exe_escaped}|" "AppDir/bin/${APPNAME}.hook"
sed -i "s|TRICKS_HERE|${TRICKS}|" "AppDir/bin/${APPNAME}.hook"
# WINEDLLOVERRIDES/WINEDEBUG/WINEPREFIX_SUBDIR always have real default
# values set above (never empty), so these always patch correctly as-is.
sed -i "s|WINEDLLOVERRIDES_HERE|${WINEDLLOVERRIDES}|" "AppDir/bin/${APPNAME}.hook"
sed -i "s|WINEDEBUG_HERE|${WINEDEBUG}|" "AppDir/bin/${APPNAME}.hook"
sed -i "s|WINEPREFIX_SUBDIR_HERE|${WINEPREFIX_SUBDIR}|" "AppDir/bin/${APPNAME}.hook"
# Convert the literal "AppDir" marker in INSTALL_URL to "$APPDIR"
sed -i 's|INSTALL_URL:-AppDir/|INSTALL_URL:-$APPDIR/|' "AppDir/bin/${APPNAME}.hook"

# Patch thin script
sed -i "s|MAIN_EXE_HERE|${MAIN_EXE}|" "AppDir/bin/${APPNAME}"
sed -i -z "s|APPNAME_HERE|${APPNAME}|1" "AppDir/bin/${APPNAME}"

# Patch desktop file
sed -i "s|MAIN_EXE_HERE|${MAIN_EXE}|" "${APPNAME}.desktop"
sed -i "s|APPNAME|${APPNAME}|g" "${APPNAME}.desktop"
sed -i "s|^Version=.*|Version=${VERSION}|" "${APPNAME}.desktop"
sed -i "s|^GenericName=.*|GenericName=${GENERIC_NAME}|" "${APPNAME}.desktop"
sed -i "s|^Comment=.*|Comment=${COMMENT_NAME}|" "${APPNAME}.desktop"
sed -i "s|^Categories=.*|Categories=${CATEGORIES_NAME}|" "${APPNAME}.desktop"
sed -i "s|^MimeType=.*|MimeType=${MIMETYPES_NAME}|" "${APPNAME}.desktop"

# Deploy dependencies
mkdir -p /tmp/wine
WINEPREFIX=/tmp/wine quick-sharun \
	/usr/bin/wine*             \
	/usr/lib/wine              \
	/usr/bin/msidb             \
	/usr/bin/msiexec           \
	/usr/bin/notepad           \
	/usr/bin/regedit           \
	/usr/bin/regsvr32          \
	/usr/bin/widl              \
	/usr/bin/wmc               \
	/usr/bin/wrc               \
	/usr/bin/function_grep.pl  \
	/usr/bin/cabextract        \
	/usr/lib/libfreetype.so*   \
	/usr/lib/libharfbuzz*      \
	/usr/lib/libgraphite*      \
	/usr/lib/libavcodec.so*    \
	/usr/lib/libavdevice.so*   \
	/usr/lib/libavfilter.so*   \
	/usr/lib/libavformat.so*   \
	/usr/lib/libavutil.so*     \
	/usr/lib/libswresample.so* \
	/usr/lib/libswscale.so*    \
	/usr/bin/wget              \
	/usr/bin/zenity            \
	/usr/bin/unzip             \
	/usr/lib/7zip/7z           \
	/usr/lib/7zip/7z.so

# Install latest winetricks
wget --retry-connrefused --tries=30 https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -O ./AppDir/bin/winetricks
chmod +x ./AppDir/bin/winetricks

# alright here the pain starts
ln -sr ./AppDir/lib/wine/x86_64-unix/*.so* ./AppDir/bin

# this gets broken by sharun somehow
kek=.$(tr -dc 'A-Za-z0-9_=-' < /dev/urandom | head -c 10)
rm -f ./AppDir/lib/wine/x86_64-unix/wine
cp /usr/lib/wine/x86_64-unix/wine ./AppDir/lib/wine/x86_64-unix/wine
patchelf --set-interpreter /tmp/"$kek" ./AppDir/lib/wine/x86_64-unix/wine
# we used to run patchelf --add-needed anylinux.so on the wine binary
# but after 11.8 this causes the binary to break horribly:
# AppDir/lib/wine/x86_64-unix/wine: oops... not enough space for load commands
# so we will ahve to make sure anylinux.so loads by adding it as a dependency to the libc
patchelf --add-needed anylinux.so ./AppDir/shared/lib/libc.so.6

cat <<EOF > ./AppDir/bin/random-linker.src.hook
#!/bin/sh
cp -f "\$APPDIR"/shared/lib/ld-linux*.so* /tmp/"$kek"
EOF
chmod +x ./AppDir/bin/*.hook

# Set the lib path to also use wine libs
# shellcheck disable=SC2016
echo 'LD_LIBRARY_PATH=${APPDIR}/lib:${APPDIR}/lib/pulseaudio:${APPDIR}/lib/alsa-lib:${APPDIR}/lib/wine/x86_64-unix' >> ./AppDir/.env

# remove wine static libs
find ./AppDir/lib/ -type f -name '*.a'
find ./AppDir/lib/ -type f -name '*.a' -delete

# strip windows libs, inspired by alpine linux: 
# https://gitlab.alpinelinux.org/alpine/aports/-/blob/master/community/wine/APKBUILD
if [ "$ARCH" = 'x86_64' ]; then
	x86_64-w64-mingw32-strip -R .comment --strip-unneeded ./AppDir/lib/wine/x86_64-windows/*.dll
	i686-w64-mingw32-strip   -R .comment --strip-unneeded ./AppDir/lib/wine/i386-windows/*.dll
fi

# Disable FileOpenAssociations
sed -i 's|    LicenseInformation|    LicenseInformation,\\\n    FileOpenAssociations|g;$a \\n[FileOpenAssociations]\nHKCU,Software\\Wine\\FileOpenAssociations,"Enable",,"N"' AppDir/share/wine/wine.inf

# Disable winemenubuilder
sed -i 's|    FileOpenAssociations|    FileOpenAssociations,\\\n    DllOverrides|;$a \\n[DllOverrides]\nHKCU,Software\\Wine\\DllOverrides,"*winemenubuilder.exe",,""' AppDir/share/wine/wine.inf
sed -i '/\%11\%\\winemenubuilder.exe -a -r/d' AppDir/share/wine/wine.inf

# Turn AppDir into AppImage
quick-sharun --make-appimage

# Test the app for 12 seconds, if the test fails due to the app
# having issues running in the CI use --simple-test instead
APPRUN_DEBUG=1 quick-sharun --test ./dist/*.AppImage
