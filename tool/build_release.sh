#!/usr/bin/env bash
#
# Builds a LifeDNA OS release artefact with every --dart-define wired.
#
# The defines are the whole reason this script exists. Miss FIREBASE_PROJECT_ID
# and the build succeeds and runs in local mode — no sync, no error. Miss
# GOOGLE_SERVER_CLIENT_ID and it succeeds and Google Sign-In returns no ID
# token. Neither failure is visible until a tester hits it, so they are checked
# here rather than trusted to a shell history.
#
#   set -a && . app/.env.release && set +a
#   tool/build_release.sh prod both
#
# Artefacts:
#   app/build/app/outputs/flutter-apk/app-<flavor>-release.apk
#   app/build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab
#   app/build/app/outputs/mapping/<flavor>Release/mapping.txt
#
set -euo pipefail

FLAVOR="${1:-prod}"
TARGET="${2:-both}"   # apk | aab | both
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$FLAVOR" in dev|staging|prod) ;; *) echo "Unknown flavor '$FLAVOR'"; exit 2 ;; esac
case "$TARGET" in apk|aab|both) ;; *) echo "Unknown target '$TARGET'"; exit 2 ;; esac

UPPER="$(printf '%s' "$FLAVOR" | tr '[:lower:]' '[:upper:]')"
VAR="GOOGLE_SERVER_CLIENT_ID_$UPPER"
CLIENT_ID="${!VAR:-${GOOGLE_SERVER_CLIENT_ID:-}}"

# Two supported modes.
#
# PERSONAL (no Firebase variables set): the app runs entirely on-device. Hive
# is the only store, there is no sign-in, and backups are the safety net. This
# is a first-class configuration, not a degraded one — it is the right setup
# for one person on one phone, and it removes every cloud failure mode at once.
#
# CLOUD (Firebase variables set): adds sync and sign-in, and then all four
# variables plus a client id are required, because a partial configuration
# builds successfully and fails silently on the phone.
SET_COUNT=0
for v in FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_SENDER_ID FIREBASE_PROJECT_ID; do
  [ -n "${!v:-}" ] && SET_COUNT=$((SET_COUNT + 1))
done

DEFINES=("--dart-define=FLAVOR=$FLAVOR")

if [ "$SET_COUNT" -eq 0 ]; then
  MODE="personal, local-only"
  echo "No Firebase variables set — building in PERSONAL mode."
  echo "  Everything stays on the phone. Back it up from Settings -> Data."
else
  MODE="cloud"
  MISSING=""
  for v in FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_SENDER_ID FIREBASE_PROJECT_ID; do
    [ -n "${!v:-}" ] || MISSING="$MISSING $v"
  done
  if [ -n "$MISSING" ]; then
    echo "Partial Firebase configuration. Missing:$MISSING"
    echo "A partial config builds fine and then fails silently on the phone."
    echo "Set all four, or none at all for a personal local-only build."
    exit 1
  fi
  if [ -z "$CLIENT_ID" ]; then
    echo "Neither $VAR nor GOOGLE_SERVER_CLIENT_ID is set."
    echo "The build would succeed and Google Sign-In would return no ID token."
    echo "See docs/mvp/18-google-auth-verification.md."
    exit 1
  fi
  DEFINES+=(
    "--dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY"
    "--dart-define=FIREBASE_APP_ID=$FIREBASE_APP_ID"
    "--dart-define=FIREBASE_SENDER_ID=$FIREBASE_SENDER_ID"
    "--dart-define=FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"
    "--dart-define=FIREBASE_STORAGE_BUCKET=${FIREBASE_STORAGE_BUCKET:-}"
    "--dart-define=GOOGLE_SERVER_CLIENT_ID_$UPPER=$CLIENT_ID"
    "--dart-define=GOOGLE_CALENDAR_CLIENT_ID=${GOOGLE_CALENDAR_CLIENT_ID:-}"
  )
fi

cd "$ROOT/app"
flutter pub get

build() {
  echo
  echo "==> flutter build $1 --flavor $FLAVOR --release   [$MODE]"
  flutter build "$1" --flavor "$FLAVOR" --release "${DEFINES[@]}"
}

# Explicit ifs, not `a || b && c`: under `set -e` that chain exits the script
# when a single-target build makes the whole compound return non-zero.
if [ "$TARGET" = "apk" ] || [ "$TARGET" = "both" ]; then
  build apk
fi
if [ "$TARGET" = "aab" ] || [ "$TARGET" = "both" ]; then
  build appbundle
fi

MAPPING="build/app/outputs/mapping/${FLAVOR}Release/mapping.txt"
echo
if [ -f "$MAPPING" ]; then
  echo "R8 mapping: app/$MAPPING"
  echo "  Keep it. R8 renames every class, the file is regenerated on each"
  echo "  build, and an artefact kept without its mapping can never be"
  echo "  symbolicated again — every beta crash report would be unreadable."
else
  echo "WARNING: no mapping.txt. Crashlytics reports will be obfuscated."
fi

echo
echo "Artefacts:"
find build/app/outputs -name "*${FLAVOR}*.apk" -o -name "*${FLAVOR}*.aab" 2>/dev/null |
  while read -r f; do printf '  %-72s %s\n' "app/$f" "$(du -h "$f" | cut -f1)"; done
