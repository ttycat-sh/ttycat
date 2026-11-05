#!/bin/sh
# The firmware for a release, in firmware/build-release: the only build that says it's ttycat's own.
# Needs ESP-IDF in the shell (. export.sh). app/release.sh won't go without it.
set -eu
cd "$(dirname "$0")/../firmware"
rm -rf build-release
idf.py -B build-release -D FW_RELEASE=1 build
