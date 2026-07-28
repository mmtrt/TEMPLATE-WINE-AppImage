#!/bin/sh

set -eu

ARCH=$(uname -m)

# Detect REQUIRE_SHARED_WINE_APPIMAGE from make-appimage.sh
if grep -q 'REQUIRE_SHARED_WINE_APPIMAGE="1"' make-appimage.sh 2>/dev/null; then
    REQUIRE_SHARED_WINE_APPIMAGE=1
    echo "REQUIRE_SHARED_WINE_APPIMAGE=1 (shared AppImage mode)"
else
    REQUIRE_SHARED_WINE_APPIMAGE=0
fi

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"

if [ "$REQUIRE_SHARED_WINE_APPIMAGE" = "1" ]; then
    pacman -Syu --noconfirm 7zip unzip
else
    pacman -Syu --noconfirm wine cabextract sdl2 pipewire-audio pipewire-jack \
        harfbuzz gst-plugins-bad gst-plugins-base gst-plugins-base-libs \
        gst-plugins-good gst-plugins-ugly gst-libav gstreamer 7zip unzip

    echo "Installing debloated packages..."
    echo "---------------------------------------------------------------"
    get-debloated-pkgs --add-common --prefer-nano ffmpeg-mini

    if [ "$ARCH" = 'x86_64' ]; then
        sudo pacman -S --noconfirm mingw-w64-binutils
    fi
fi

# Download shared Wine AppImage if enabled
if [ "$REQUIRE_SHARED_WINE_APPIMAGE" = "1" ]; then
    echo "Downloading latest Wine AppImage..."

    TAG=$(wget -qO- 'https://github.com/pkgforge-dev/wine-AppImage/releases' | \
          grep -oE 'releases/tag/[^"]+' | head -1 | cut -d'/' -f3)

    WINE_VER=$(wget -qO- 'https://github.com/pkgforge-dev/wine-AppImage/releases' | \
           grep -oE 'wine:[[:space:]]*[0-9.]+-[0-9]+' | head -1 | awk '{print $2}')

    if [ -n "$TAG" ] && [ -n "$WINE_VER" ]; then
        wget -q --content-disposition \
          "https://github.com/pkgforge-dev/wine-AppImage/releases/download/${TAG}/wine-${WINE_VER}-anylinux-x86_64.AppImage" \
          -O /tmp/wine.AppImage && chmod +x /tmp/wine.AppImage
        echo "WINE_APPIMAGE_PATH=${WINE_APPIMAGE_PATH:-/tmp/wine.AppImage}" >> $GITHUB_ENV
    else
        echo "Failed to fetch latest Wine AppImage" >&2
        exit 1
    fi
fi

# Comment this out if you need an AUR package
make-aur-package zenity-rs-bin

# If the application needs to be manually built that has to be done down here
