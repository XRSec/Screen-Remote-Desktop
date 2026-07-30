#!/bin/sh

set -eu

VERSION="4.1"
SHA256="deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSET_DIR="$PROJECT_DIR/assets"
ASSET="$ASSET_DIR/scrcpy-server.jar"
URL="https://github.com/Genymobile/scrcpy/releases/download/v$VERSION/scrcpy-server-v$VERSION"
LICENSE_ASSET="$ASSET_DIR/scrcpy-LICENSE.txt"
LICENSE_URL="https://raw.githubusercontent.com/Genymobile/scrcpy/v$VERSION/LICENSE"
LICENSE_SHA256="01c12035bf35af37241298dc7ad538eb2a07e5c940437bc6876feeaa9d1951d0"

checksum() {
    shasum -a 256 "$1" | awk '{print $1}'
}

mkdir -p "$ASSET_DIR"

if [ -f "$ASSET" ]; then
    actual="$(checksum "$ASSET")"
    if [ "$actual" != "$SHA256" ]; then
        echo "scrcpy-server checksum mismatch: expected=$SHA256 actual=$actual" >&2
        exit 1
    fi
    echo "Verified macOS scrcpy-server asset: v$VERSION"
else
    temporary="$ASSET.download.$$"
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    echo "Downloading official scrcpy-server v$VERSION for the macOS asset bundle"
    curl --fail --location --retry 3 --connect-timeout 15 --output "$temporary" "$URL"
    actual="$(checksum "$temporary")"
    if [ "$actual" != "$SHA256" ]; then
        echo "Downloaded scrcpy-server checksum mismatch: expected=$SHA256 actual=$actual" >&2
        exit 1
    fi
    mv "$temporary" "$ASSET"
    trap - EXIT HUP INT TERM
    echo "Created macOS scrcpy-server asset: $ASSET"
fi

if [ -f "$LICENSE_ASSET" ]; then
    actual="$(checksum "$LICENSE_ASSET")"
    if [ "$actual" != "$LICENSE_SHA256" ]; then
        echo "scrcpy license checksum mismatch: expected=$LICENSE_SHA256 actual=$actual" >&2
        exit 1
    fi
else
    temporary="$LICENSE_ASSET.download.$$"
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    echo "Downloading the scrcpy v$VERSION license for the macOS asset bundle"
    curl --fail --location --retry 3 --connect-timeout 15 --output "$temporary" "$LICENSE_URL"
    actual="$(checksum "$temporary")"
    if [ "$actual" != "$LICENSE_SHA256" ]; then
        echo "Downloaded scrcpy license checksum mismatch: expected=$LICENSE_SHA256 actual=$actual" >&2
        exit 1
    fi
    mv "$temporary" "$LICENSE_ASSET"
    trap - EXIT HUP INT TERM
fi

if [ "$#" -eq 2 ] && [ "$1" = "--copy-to" ]; then
    destination="$2"
    mkdir -p "$destination"
    cp "$ASSET" "$destination/scrcpy-server.jar"
    cp "$LICENSE_ASSET" "$destination/scrcpy-LICENSE.txt"
    echo "Bundled scrcpy-server.jar and its license into application resources"
elif [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--copy-to RESOURCE_DIRECTORY]" >&2
    exit 2
fi
