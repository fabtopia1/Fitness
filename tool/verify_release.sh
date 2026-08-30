#!/usr/bin/env bash
#
# Release preflight for LifeDNA OS.
#
# Checks everything that can be checked WITHOUT running a Gradle build, so a
# misconfiguration is caught in seconds rather than after a 20-minute CI run or,
# worse, on a tester's phone. Exits non-zero on any blocker.
#
#   tool/verify_release.sh prod
#
set -uo pipefail

FLAVOR="${1:-prod}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/app"
ANDROID="$APP/android"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; OFF=$'\033[0m'
BLOCKERS=0
WARNINGS=0

pass() { printf '  %sPASS%s  %s\n' "$GREEN" "$OFF" "$1"; }
warn() { printf '  %sWARN%s  %s\n' "$YELLOW" "$OFF" "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  %sBLOCK%s %s\n' "$RED" "$OFF" "$1"; BLOCKERS=$((BLOCKERS + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

case "$FLAVOR" in
  dev|staging|prod) ;;
  *) echo "Unknown flavor '$FLAVOR' (expected dev, staging or prod)"; exit 2 ;;
esac

printf '\033[1mLifeDNA OS — release preflight (%s)\033[0m\n' "$FLAVOR"

# ---------------------------------------------------------------- toolchain --
section "Toolchain"
if command -v flutter >/dev/null 2>&1; then
  pass "flutter $(flutter --version 2>/dev/null | grep -oE '^Flutter [0-9.]+' | cut -d' ' -f2)"
else
  fail "flutter is not on PATH"
fi
if command -v java >/dev/null 2>&1; then
  JAVA_MAJOR="$(java -version 2>&1 | grep -E 'version "' | head -1 |
                 grep -oE '"[0-9]+' | tr -d '"')"
  if [ "${JAVA_MAJOR:-0}" -ge 17 ]; then
    pass "JDK $JAVA_MAJOR (AGP 9 needs 17+)"
  else
    fail "JDK $JAVA_MAJOR is below the 17 that AGP 9 requires"
  fi
else
  fail "java is not on PATH"
fi
if [ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]; then
  pass "Android SDK at ${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
else
  fail "ANDROID_HOME / ANDROID_SDK_ROOT is unset — Gradle cannot build"
fi

# ------------------------------------------------------------------ signing --
section "Release signing"
KEY_PROPS="$ANDROID/key.properties"
if [ "$FLAVOR" = "dev" ]; then
  pass "dev builds debug — no release keystore needed"
elif [ ! -f "$KEY_PROPS" ]; then
  fail "no android/key.properties — the release build would be DEBUG-SIGNED. Play rejects it and Google Sign-In fails against an unregistered SHA-1."
else
  MISSING=""
  for k in keyAlias keyPassword storeFile storePassword; do
    grep -qE "^${k}=.+" "$KEY_PROPS" || MISSING="$MISSING $k"
  done
  if [ -n "$MISSING" ]; then
    fail "key.properties is missing:$MISSING"
  else
    STORE="$(grep -E '^storeFile=' "$KEY_PROPS" | cut -d= -f2-)"
    case "$STORE" in /*) STORE_PATH="$STORE" ;; *) STORE_PATH="$ANDROID/app/$STORE" ;; esac
    if [ -f "$STORE_PATH" ]; then
      pass "keystore present at $STORE_PATH"
      if command -v keytool >/dev/null 2>&1; then
        ALIAS="$(grep -E '^keyAlias=' "$KEY_PROPS" | cut -d= -f2-)"
        PW="$(grep -E '^storePassword=' "$KEY_PROPS" | cut -d= -f2-)"
        SHA1="$(keytool -list -v -alias "$ALIAS" -keystore "$STORE_PATH" \
                 -storepass "$PW" 2>/dev/null | grep -oE 'SHA1: [0-9A-F:]+' | head -1)"
        if [ -n "$SHA1" ]; then
          pass "release $SHA1"
          printf '        Register this in Firebase for the flavour package name.\n'
        else
          warn "could not read the SHA-1 — check keyAlias and storePassword"
        fi
      fi
    else
      fail "storeFile points at $STORE_PATH, which does not exist"
    fi
  fi
fi

# ------------------------------------------------------------------ firebase --
section "Firebase"
GS=""
for candidate in "$ANDROID/app/src/$FLAVOR/google-services.json" "$ANDROID/app/google-services.json"; do
  [ -f "$candidate" ] && GS="$candidate" && break
done
if [ -z "$GS" ]; then
  fail "no google-services.json for '$FLAVOR' — the Gradle plugins will not be applied, so Google Sign-In returns no ID token and Crashlytics uploads no mapping"
else
  pass "google-services.json at ${GS#"$ROOT/"}"
  EXPECTED_PKG="os.lifedna.lifedna"
  [ "$FLAVOR" = "prod" ] || EXPECTED_PKG="os.lifedna.lifedna.$FLAVOR"
  if grep -q "\"$EXPECTED_PKG\"" "$GS"; then
    pass "declares $EXPECTED_PKG"
  else
    fail "does not declare $EXPECTED_PKG — Google Sign-In will fail with ApiException: 10"
  fi
  if grep -q '"client_type": 3' "$GS"; then
    pass "contains a web client (the ID-token audience)"
  else
    warn "no web client in the file — pass GOOGLE_SERVER_CLIENT_ID explicitly"
  fi
  if grep -qE '"certificate_hash"' "$GS"; then
    pass "at least one signing certificate is registered"
  else
    fail "no certificate_hash — no SHA-1 registered, so the account picker will not open"
  fi
fi

# ------------------------------------------------------------- dart-defines --
section "Build-time configuration"
VAR="GOOGLE_SERVER_CLIENT_ID_$(printf '%s' "$FLAVOR" | tr '[:lower:]' '[:upper:]')"
CLIENT_ID="${!VAR:-${GOOGLE_SERVER_CLIENT_ID:-}}"
if [ -z "$CLIENT_ID" ]; then
  if [ -n "$GS" ] && grep -q '"client_type": 3' "$GS"; then
    warn "$VAR unset — falling back to the generated default_web_client_id"
  else
    fail "$VAR unset and no web client in google-services.json — sign-in cannot get an ID token"
  fi
else
  case "$CLIENT_ID" in
    *.apps.googleusercontent.com) pass "$VAR looks like an OAuth client id" ;;
    *) fail "$VAR is not an OAuth client id: $CLIENT_ID" ;;
  esac
fi
for v in FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_SENDER_ID FIREBASE_PROJECT_ID; do
  if [ -z "${!v:-}" ]; then
    fail "$v is unset — the build would run in local mode with no cloud sync"
  else
    pass "$v set"
  fi
done

# ------------------------------------------------------------------- source --
section "Source gates"
cd "$APP" || exit 1
if flutter analyze --fatal-infos >/dev/null 2>&1; then pass "analyze"; else fail "flutter analyze"; fi
if dart format --output=none --set-exit-if-changed lib test integration_test >/dev/null 2>&1; then
  pass "format"
else
  fail "dart format"
fi
if python3 tool/check_sources.py >/dev/null 2>&1; then pass "layer + colour rules"; else fail "check_sources.py"; fi
if flutter test >/dev/null 2>&1; then pass "test suite"; else fail "flutter test"; fi

# ------------------------------------------------------------------- verdict --
section "Verdict"
if [ "$BLOCKERS" -gt 0 ]; then
  printf '  %s%d blocker(s)%s, %d warning(s). NOT READY to build %s.\n\n' \
    "$RED" "$BLOCKERS" "$OFF" "$WARNINGS" "$FLAVOR"
  exit 1
fi
printf '  %sReady to build %s%s (%d warning(s)).\n\n' "$GREEN" "$FLAVOR" "$OFF" "$WARNINGS"
