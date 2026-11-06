#!/bin/sh
# The firmware for a release, in firmware/build-release: the only build that says it's ttycat's own.
# Then the same source as a signed core release, in firmware/build-release-core, which the app builds
# for boards of people's own. Signing needs the key in TTYCAT_SIGNING_KEY: see tools/release_key.py.
# Needs ESP-IDF in the shell (. export.sh). app/release.sh won't go without either.
set -eu
cd "$(dirname "$0")/../firmware"
rm -rf build-release build-release-core
idf.py -B build-release -D FW_RELEASE=1 build
python3 ../tools/release_core.py build-release-core
