#!/usr/bin/env bash
# Wrap a Developer ID-signed Pulse.app in a drag-to-Applications DMG.
# Optional: notarize and staple the DMG with the same credentials as notarize.sh.
# See docs/RELEASE.md. Does not write secrets into the repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=notarize.sh
source "${ROOT}/scripts/notarize.sh"

pulse_dmg_usage() {
  cat <<EOF
Usage: ./scripts/make-dmg.sh [--app PATH] [--output PATH] [--notarize]

Build a UDZO disk image containing Pulse.app and an Applications symlink.
The app must already be Developer ID signed (run ./scripts/notarize.sh first).

  --app PATH       default: build/export/Pulse.app
  --output PATH    default: build/Pulse-<version>.dmg
  --notarize       submit the DMG to notarytool and staple it
  -h, --help

--notarize uses the same environment as scripts/notarize.sh:
  DEVELOPMENT_TEAM, and NOTARY_KEYCHAIN_PROFILE
  or APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD.
The Developer ID identity must still be in the keychain. Do not commit secrets.
EOF
}

pulse_dmg_main() {
  local notarize=0
  local app=""
  local output=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        pulse_dmg_usage
        exit 0
        ;;
      --notarize)
        notarize=1
        shift
        ;;
      --app)
        if [[ $# -lt 2 ]]; then
          pulse_fail "--app requires a path to Pulse.app"
        fi
        app="$2"
        shift 2
        ;;
      --output)
        if [[ $# -lt 2 ]]; then
          pulse_fail "--output requires a path"
        fi
        output="$2"
        shift 2
        ;;
      *)
        pulse_fail "unknown option: $1 (see --help)"
        ;;
    esac
  done

  pulse_refuse_xtrace
  pulse_require_macos
  if ! command -v hdiutil >/dev/null 2>&1 || ! command -v ditto >/dev/null 2>&1; then
    pulse_fail "hdiutil and ditto are required to build a DMG."
  fi

  if [[ -z "$app" ]]; then
    app="${ROOT}/build/export/Pulse.app"
  fi
  if [[ ! -d "$app" ]]; then
    pulse_fail "missing app bundle: ${app}. Run ./scripts/notarize.sh first, or pass --app."
  fi
  pulse_assert_signed_app "$app"

  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app}/Contents/Info.plist" 2>/dev/null || true)"
  if [[ -z "$version" ]]; then
    version="0.1.0"
  fi
  if [[ -z "$output" ]]; then
    output="${ROOT}/build/Pulse-${version}.dmg"
  fi

  if [[ "$notarize" -eq 1 ]]; then
    pulse_require_tools
    pulse_check_team "${DEVELOPMENT_TEAM:-}"
    local listing
    listing="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    IDENTITY="$(pulse_select_identity "$DEVELOPMENT_TEAM" "${CODE_SIGN_IDENTITY:-}" "$listing")"
    pulse_check_notary_env
    echo "team: ${DEVELOPMENT_TEAM}"
    echo "identity: ${IDENTITY}"
  fi

  local stage
  stage="$(mktemp -d "${TMPDIR:-/tmp}/pulse-dmg.XXXXXX")"
  trap 'rm -rf "$stage"' EXIT
  ditto "$app" "${stage}/Pulse.app"
  ln -s /Applications "${stage}/Applications"
  mkdir -p "$(dirname "$output")"
  rm -f "$output"
  hdiutil create \
    -volname "Pulse" \
    -srcfolder "$stage" \
    -ov \
    -format UDZO \
    "$output"

  if [[ "$notarize" -eq 1 ]]; then
    echo "submit: ${output}"
    pulse_notary_submit "$output"
    xcrun stapler staple "$output"
    xcrun stapler validate "$output"
    echo "stapled dmg: ${output}"
  else
    echo "dmg: ${output}"
    echo "notarize it with: ./scripts/make-dmg.sh --notarize"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  pulse_dmg_main "$@"
fi
