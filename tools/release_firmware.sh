#!/bin/sh
# A release, signed with the key in TTYCAT_SIGNING_KEY (see tools/release_key.py):
#   firmware/build-release        the build: the only one that says it's ttycat's own
#   firmware/build-release-image  its image, signed, which the app carries and the update server offers
#   firmware/build-release-core   the same source as a core release, which the app builds for boards
#                                 of people's own
# Needs ESP-IDF in the shell (. export.sh). app/release.sh won't go without all three.
set -eu
cd "$(dirname "$0")/../firmware"
[ -n "${TTYCAT_SIGNING_KEY:-}" ] || { echo "TTYCAT_SIGNING_KEY isn't set: see tools/release_key.py" >&2; exit 1; }
rm -rf build-release build-release-image build-release-core
idf.py -B build-release -D FW_RELEASE=1 build
python3 ../tools/firmware_bundle.py build-release build-release-image --sign
python3 ../tools/release_core.py build-release-core
