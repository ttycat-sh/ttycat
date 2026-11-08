#!/bin/sh
# A release, signed with the key in TTYCAT_SIGNING_KEY (see daemon/tools/release_key.py):
#   build-release        the build: the only one that says it's ttycat's own
#   build-release-image  its image, signed, which the app carries and the update server offers
#   build-release-core   the same source as a core release, which the app builds for boards of people's own
# Needs ESP-IDF in the shell (. export.sh), and the daemon: git submodule update --init daemon.
# ttycat-app's release.sh won't go without all three.
set -eu
cd "$(dirname "$0")/.."
[ -f daemon/release.py ] || { echo "no daemon: git submodule update --init daemon" >&2; exit 1; }
[ -n "${TTYCAT_SIGNING_KEY:-}" ] || { echo "TTYCAT_SIGNING_KEY isn't set: see daemon/tools/release_key.py" >&2; exit 1; }
rm -rf build-release build-release-image build-release-core
idf.py -B build-release -D FW_RELEASE=1 build
python3 daemon/tools/firmware_bundle.py build-release build-release-image --sign
python3 daemon/tools/release_core.py . build-release-core
