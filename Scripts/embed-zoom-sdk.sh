#!/bin/bash
set -euo pipefail

# Embed the real Zoom SDK frameworks from the xcframework slices.
# Without this, relaunching the app from the home screen crashes in dyld because
# only the stub wrapper frameworks are copied into the app bundle.

if [ "${ACTION:-}" = "clean" ]; then
  exit 0
fi

FRAMEWORKS_FOLDER="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "${FRAMEWORKS_FOLDER}"

if [ "${PLATFORM_NAME}" = "iphonesimulator" ]; then
  SLICE="ios-arm64-simulator"
else
  SLICE="ios-arm64"
fi

embed_framework() {
  local xcframework_path="$1"
  local framework_name="$2"
  local source="${xcframework_path}/${SLICE}/${framework_name}"
  local destination="${FRAMEWORKS_FOLDER}/${framework_name}"

  if [ ! -d "${source}" ]; then
    echo "error: Missing ${source}" >&2
    exit 1
  fi

  rm -rf "${destination}"
  cp -Rf "${source}" "${destination}"

  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      --preserve-metadata=identifier,entitlements,flags --timestamp=none "${destination}"
  fi
}

embed_framework "${SRCROOT}/Learning/MobileRTC.xcframework" "MobileRTC.framework"
embed_framework "${SRCROOT}/Learning/zoomcml.xcframework" "zoomcml.framework"
