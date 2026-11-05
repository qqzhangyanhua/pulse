#!/usr/bin/env bash
# Archive Pulse with a Developer ID Application certificate, export, submit to
# notarytool, and staple the ticket. Secrets stay in the environment or the
# login keychain. This script never writes them to the repo.
#
# See docs/RELEASE.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pulse_fail() {
  echo "error: $*" >&2
  exit 1
}

pulse_refuse_xtrace() {
  case "$-" in
    *x*)
      pulse_fail "refusing to run under xtrace (bash -x); it can print the notary password. Run ./scripts/notarize.sh without -x."
      ;;
  esac
}

pulse_require_macos() {
  local os
  os="$(uname -s)"
  if [[ "$os" != "Darwin" ]]; then
    pulse_fail "this step runs on macOS with Xcode (this host is ${os}). Install a Developer ID Application certificate there, then run the script. Local Debug on that Mac stays ad-hoc (CODE_SIGN_IDENTITY=- in the Xcode project)."
  fi
}

pulse_check_team() {
  local team="${1-}"
  if [[ -z "$team" ]]; then
    pulse_fail "DEVELOPMENT_TEAM is empty. Export the 10-character Apple Team ID in the environment. Do not commit it. Example: DEVELOPMENT_TEAM=ABCDE12345 ./scripts/notarize.sh"
  fi
  if [[ ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then
    pulse_fail "DEVELOPMENT_TEAM must be 10 letters or digits (A-Z, 0-9). The value was not printed (length ${#team})."
  fi
}

pulse_xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# Print Developer ID Application common names, one per line.
pulse_developer_id_names() {
  printf '%s\n' "$1" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p'
}

# Resolve the signing identity. Prints the common name on stdout.
# $1 team, $2 requested CODE_SIGN_IDENTITY (may be empty), $3 find-identity listing.
pulse_select_identity() {
  local team="$1"
  local requested="$2"
  local listing="$3"
  local line name found
  local names matched
  names=()
  matched=()

  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      names+=("$line")
    fi
  done < <(pulse_developer_id_names "$listing")

  if [[ ${#names[@]} -eq 0 ]]; then
    pulse_fail "no Developer ID Application identity in the login keychain. Install a Developer ID Application certificate (not Apple Development, and not a Mac App Store certificate). This script does not create a certificate and does not store secrets. Local Debug stays CODE_SIGN_IDENTITY=-."
  fi

  for name in "${names[@]}"; do
    if [[ "$name" == *"($team)" ]]; then
      matched+=("$name")
    fi
  done

  case "$requested" in
    -|ad-hoc|adhoc|"Ad Hoc"|"Sign to Run Locally")
      pulse_fail "CODE_SIGN_IDENTITY is ad-hoc. notarize.sh needs a Developer ID Application certificate. Keep CODE_SIGN_IDENTITY=- for local Debug only."
      ;;
    "Apple Development"*|"Apple Distribution"*|"Mac Developer"*|"3rd Party Mac Developer"*)
      pulse_fail "CODE_SIGN_IDENTITY must be a Developer ID Application certificate. The current value cannot be notarized for direct install."
      ;;
  esac

  if [[ -z "$requested" || "$requested" == "Developer ID Application" ]]; then
    if [[ ${#matched[@]} -eq 0 ]]; then
      pulse_fail "no Developer ID Application certificate for team ${team}. The keychain has ${#names[@]} Developer ID identity(ies) for other teams. Install the certificate for this team, or point DEVELOPMENT_TEAM at the team in the certificate name."
    fi
    if [[ ${#matched[@]} -gt 1 ]]; then
      echo "multiple Developer ID Application certificates for team ${team}:" >&2
      for name in "${matched[@]}"; do
        echo "  ${name}" >&2
      done
      pulse_fail "set CODE_SIGN_IDENTITY to one full certificate name."
    fi
    printf '%s\n' "${matched[0]}"
    return 0
  fi

  found=""
  for name in "${names[@]}"; do
    if [[ "$name" == "$requested" ]]; then
      found="$name"
      break
    fi
  done
  if [[ -z "$found" ]]; then
    pulse_fail "CODE_SIGN_IDENTITY does not match a codesigning identity. Use the full name from: security find-identity -v -p codesigning"
  fi
  if [[ "$found" != *"($team)" ]]; then
    pulse_fail "CODE_SIGN_IDENTITY is not for DEVELOPMENT_TEAM ${team}."
  fi
  printf '%s\n' "$found"
}

pulse_check_notary_env() {
  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    if [[ -n "${APPLE_TEAM_ID:-}" && "${APPLE_TEAM_ID}" != "${DEVELOPMENT_TEAM}" ]]; then
      pulse_fail "APPLE_TEAM_ID does not match DEVELOPMENT_TEAM. Use one Team ID for signing and notarization."
    fi
    return 0
  fi
  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    pulse_fail "set NOTARY_KEYCHAIN_PROFILE, or both APPLE_ID and APPLE_APP_SPECIFIC_PASSWORD. Create a profile with: xcrun notarytool store-credentials \"pulse-notary\" --apple-id \"you@example.com\" --team-id \"\$DEVELOPMENT_TEAM\" --password \"@env:APPLE_APP_SPECIFIC_PASSWORD\". Do not commit the password."
  fi
  if [[ -n "${APPLE_TEAM_ID:-}" && "${APPLE_TEAM_ID}" != "${DEVELOPMENT_TEAM}" ]]; then
    pulse_fail "APPLE_TEAM_ID does not match DEVELOPMENT_TEAM. Use one Team ID for signing and notarization."
  fi
  # notarytool reads @env: only from the environment of this process.
  export APPLE_APP_SPECIFIC_PASSWORD
}

pulse_notary_team() {
  printf '%s' "${APPLE_TEAM_ID:-$DEVELOPMENT_TEAM}"
}

# $1 file to submit (.zip, .dmg, or .pkg). Does not print the app-specific password.
pulse_notary_submit() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    pulse_fail "nothing to submit: ${file}"
  fi
  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "notarytool: keychain profile ${NOTARY_KEYCHAIN_PROFILE}"
    xcrun notarytool submit "$file" \
      --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
      --wait
    return 0
  fi
  echo "notarytool: Apple ID ${APPLE_ID} (app-specific password not shown)"
  xcrun notarytool submit "$file" \
    --apple-id "$APPLE_ID" \
    --password "@env:APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$(pulse_notary_team)" \
    --wait
}

pulse_require_tools() {
  local t
  local missing
  missing=()
  for t in xcodebuild xcrun security codesign ditto spctl; do
    if ! command -v "$t" >/dev/null 2>&1; then
      missing+=("$t")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    pulse_fail "missing tools: ${missing[*]}. Install Xcode (and the command line tools)."
  fi
  if ! xcrun --find notarytool >/dev/null 2>&1; then
    pulse_fail "xcrun notarytool was not found. Install Xcode."
  fi
  if ! xcrun --find stapler >/dev/null 2>&1; then
    pulse_fail "xcrun stapler was not found. Install Xcode."
  fi
}

pulse_assert_signed_app() {
  local app="$1"
  local info ents
  if [[ ! -d "$app" ]]; then
    pulse_fail "app bundle not found: ${app}"
  fi
  if ! info="$(codesign -dv --verbose=4 "$app" 2>&1)"; then
    pulse_fail "codesign could not read a signature on ${app}"
  fi
  if printf '%s\n' "$info" | grep -Eq 'Signature=adhoc|flags=.*\(adhoc\)'; then
    pulse_fail "${app} is ad-hoc signed. Run ./scripts/notarize.sh after a Developer ID Application certificate is installed. CODE_SIGN_IDENTITY=- is only for local Debug."
  fi
  if ! printf '%s\n' "$info" | grep -q "Developer ID Application"; then
    pulse_fail "${app} is not signed with a Developer ID Application certificate."
  fi
  if ! printf '%s\n' "$info" | grep -Eq 'flags=.*\(runtime\)'; then
    pulse_fail "${app} is missing the hardened runtime flag."
  fi
  if printf '%s\n' "$info" | grep -q "Timestamp=none"; then
    pulse_fail "${app} has no secure timestamp. Notarization requires one."
  fi
  ents="$(codesign -d --entitlements :- "$app" 2>/dev/null || true)"
  if printf '%s\n' "$ents" | grep -q "com.apple.security.get-task-allow"; then
    pulse_fail "${app} contains com.apple.security.get-task-allow. A distribution build cannot be notarized with that debugger entitlement."
  fi
  if printf '%s\n' "$ents" | grep -A1 "com.apple.security.app-sandbox" | grep -q "<true/>"; then
    pulse_fail "${app} enables the app sandbox. Phase 1 keeps Pulse/Pulse.entitlements empty and ENABLE_APP_SANDBOX=NO."
  fi
}

pulse_write_export_options() {
  local path="$1"
  local cert team
  cert="$(pulse_xml_escape "$IDENTITY")"
  team="$(pulse_xml_escape "$DEVELOPMENT_TEAM")"
  cat >"$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>${cert}</string>
	<key>teamID</key>
	<string>${team}</string>
</dict>
</plist>
EOF
}

pulse_refuse_broad_delete() {
  local path="$1"
  if [[ -z "$path" || "$path" == "/" || "$path" == "." || "$path" == ".." || "$path" == "$ROOT" || "$path" == "${ROOT}/" ]]; then
    pulse_fail "refusing to remove ${path:-<empty>}"
  fi
}

pulse_archive() {
  echo "archive: Release, Developer ID, hardened runtime, sandbox off"
  pulse_refuse_broad_delete "$ARCHIVE"
  rm -rf "$ARCHIVE"
  mkdir -p "$(dirname "$ARCHIVE")"
  xcodebuild \
    -project "$ROOT/Pulse.xcodeproj" \
    -scheme Pulse \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    archive \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=${IDENTITY}" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    ENABLE_APP_SANDBOX=NO \
    CODE_SIGN_ENTITLEMENTS="Pulse/Pulse.entitlements"
}

pulse_codesign_archived_app() {
  local archived="${ARCHIVE}/Products/Applications/Pulse.app"
  if [[ ! -d "$archived" ]]; then
    pulse_fail "exportArchive failed, and ${archived} does not exist."
  fi
  echo "exportArchive failed. Signing the archived Pulse.app with codesign --options runtime --timestamp and the same Developer ID identity." >&2
  mkdir -p "$EXPORT_DIR"
  rm -rf "${EXPORT_DIR}/Pulse.app"
  ditto "$archived" "${EXPORT_DIR}/Pulse.app"
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Pulse/Pulse.entitlements" \
    --sign "$IDENTITY" \
    "${EXPORT_DIR}/Pulse.app"
}

pulse_export() {
  local plist="${EXPORT_DIR}/exportOptions.plist"
  local log="${ROOT}/build/export.log"
  mkdir -p "$ROOT/build"
  pulse_refuse_broad_delete "$EXPORT_DIR"
  rm -rf "$EXPORT_DIR"
  mkdir -p "$EXPORT_DIR"
  pulse_write_export_options "$plist"
  echo "export: developer-id → ${EXPORT_DIR}"
  if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$plist" \
    2>&1 | tee "$log"; then
    pulse_codesign_archived_app
  fi
  if [[ ! -d "${EXPORT_DIR}/Pulse.app" ]]; then
    pulse_fail "export did not produce ${EXPORT_DIR}/Pulse.app. See ${log}."
  fi
}

pulse_notarize_app() {
  local app="$1"
  local zip="${ROOT}/build/Pulse.zip"
  mkdir -p "$ROOT/build"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  echo "submit: ${zip}"
  pulse_notary_submit "$zip"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  if ! spctl --assess --type execute --verbose=4 "$app"; then
    pulse_fail "Gatekeeper did not accept ${app} after stapling."
  fi
  echo "stapled app: ${app}"
  echo "install: ditto \"${app}\" /Applications/Pulse.app"
}

pulse_usage() {
  cat <<EOF
Usage: ./scripts/notarize.sh [options]

Archive Pulse (Release), export a Developer ID app, submit it to Apple
notarytool, and staple the ticket. One command on a Mac that already has a
Developer ID Application certificate. This script does not create certificates
and does not write secrets into the repo.

Required environment:
  DEVELOPMENT_TEAM              10-character Apple Team ID

Notary credentials, one of:
  NOTARY_KEYCHAIN_PROFILE       preferred (xcrun notarytool store-credentials)
  APPLE_ID                      with APPLE_APP_SPECIFIC_PASSWORD
  APPLE_APP_SPECIFIC_PASSWORD   app-specific password; never commit it

Optional environment:
  APPLE_TEAM_ID                 defaults to DEVELOPMENT_TEAM; must match if set
  CODE_SIGN_IDENTITY            full "Developer ID Application: Name (TEAM)"
                                Required when more than one Developer ID cert
                                exists for the team. Do not set this to "-".

Options:
  --preflight                   check team, identity, and notary env, then exit
  --archive-path PATH           default: build/Pulse.xcarchive
  --export-dir PATH             default: build/export
  --skip-archive                export an existing archive
  --skip-export                 notarize build/export/Pulse.app as it is
  --app PATH                    notarize this .app (skip archive and export)
  -h, --help

Debug smoke does not use this script. The Xcode project keeps
CODE_SIGN_IDENTITY=- so Run works with no certificate.

See docs/RELEASE.md.
EOF
}

pulse_main() {
  local preflight=0
  local skip_archive=0
  local skip_export=0
  local app_path=""
  ARCHIVE="${ROOT}/build/Pulse.xcarchive"
  EXPORT_DIR="${ROOT}/build/export"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        pulse_usage
        exit 0
        ;;
      --preflight)
        preflight=1
        shift
        ;;
      --skip-archive)
        skip_archive=1
        shift
        ;;
      --skip-export)
        skip_export=1
        skip_archive=1
        shift
        ;;
      --app)
        if [[ $# -lt 2 ]]; then
          pulse_fail "--app requires a path to Pulse.app"
        fi
        app_path="$2"
        shift 2
        ;;
      --archive-path)
        if [[ $# -lt 2 ]]; then
          pulse_fail "--archive-path requires a path"
        fi
        ARCHIVE="$2"
        shift 2
        ;;
      --export-dir)
        if [[ $# -lt 2 ]]; then
          pulse_fail "--export-dir requires a path"
        fi
        EXPORT_DIR="$2"
        shift 2
        ;;
      *)
        pulse_fail "unknown option: $1 (see --help)"
        ;;
    esac
  done

  pulse_refuse_xtrace
  pulse_require_macos
  pulse_require_tools
  pulse_check_team "${DEVELOPMENT_TEAM:-}"
  if [[ ! -d "${ROOT}/Pulse.xcodeproj" ]]; then
    pulse_fail "Pulse.xcodeproj not found under ${ROOT}"
  fi

  local listing
  listing="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  IDENTITY="$(pulse_select_identity "$DEVELOPMENT_TEAM" "${CODE_SIGN_IDENTITY:-}" "$listing")"
  pulse_check_notary_env

  echo "team: ${DEVELOPMENT_TEAM}"
  echo "identity: ${IDENTITY}"
  if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "notary: keychain profile ${NOTARY_KEYCHAIN_PROFILE}"
  else
    echo "notary: Apple ID ${APPLE_ID} (app-specific password not shown)"
  fi

  if [[ "$preflight" -eq 1 ]]; then
    echo "preflight ok"
    exit 0
  fi

  local app
  if [[ -n "$app_path" ]]; then
    app="$app_path"
  else
    app="${EXPORT_DIR}/Pulse.app"
    if [[ "$skip_export" -eq 0 ]]; then
      if [[ "$skip_archive" -eq 0 ]]; then
        pulse_archive
      fi
      if [[ ! -d "$ARCHIVE" ]]; then
        pulse_fail "archive not found: ${ARCHIVE}"
      fi
      pulse_export
    fi
  fi

  pulse_assert_signed_app "$app"
  pulse_notarize_app "$app"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  pulse_main "$@"
fi
