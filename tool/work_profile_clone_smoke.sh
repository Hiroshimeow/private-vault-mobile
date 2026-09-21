#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-emulator-5554}"
ADB="${ANDROID_HOME:?ANDROID_HOME is required}/platform-tools/adb"
PACKAGE="io.hiroshimeow.private_vault_mobile"
ADMIN="${PACKAGE}/.PrivateVaultDeviceAdminReceiver"
DEBUG_RECEIVER="${PACKAGE}/.WorkProfileDebugBootstrapReceiver"
DEBUG_ACTION="io.hiroshimeow.private_vault_mobile.action.DEBUG_WORK_PROFILE_BOOTSTRAP"
APK="build/app/outputs/flutter-apk/app-debug.apk"
WORK_USER=""
SMOKE_PACKAGE=""

adb_cmd() {
  "$ADB" -s "$DEVICE" "$@"
}

dump_diagnostics() {
  set +e
  echo "::group::Managed profile diagnostics"
  echo "device=$DEVICE work_user=${WORK_USER:-unset} package=${SMOKE_PACKAGE:-unset}"
  adb_cmd shell pm list users || true
  adb_cmd shell dumpsys device_policy || true
  if [[ -n "$WORK_USER" ]]; then
    adb_cmd shell pm list packages --user "$WORK_USER" -d || true
    adb_cmd shell pm list packages --user "$WORK_USER" -e || true
    adb_cmd shell dumpsys package "$PACKAGE" || true
  fi
  echo "::endgroup::"
  set -e
}

cleanup() {
  if [[ -n "$WORK_USER" ]]; then
    adb_cmd shell am stop-user -f "$WORK_USER" >/dev/null 2>&1 || true
    adb_cmd shell pm remove-user "$WORK_USER" >/dev/null 2>&1 || true
  fi
}

on_exit() {
  local status=$?
  trap - EXIT
  if [[ $status -ne 0 ]]; then
    dump_diagnostics
  fi
  cleanup
  exit "$status"
}
trap on_exit EXIT

wait_for_profile_ready() {
  local attempt
  for attempt in {1..40}; do
    if adb_cmd shell pm path --user "$WORK_USER" "$PACKAGE" 2>/dev/null | grep -q '^package:' &&
       adb_cmd shell dumpsys device_policy 2>/dev/null | grep -Fq "$ADMIN"; then
      echo "Managed profile ready after attempt $attempt."
      return 0
    fi
    sleep 0.5
  done

  echo "Managed profile did not become ready in time." >&2
  return 1
}

flutter build apk --debug
adb_cmd install -r -t "$APK" >/dev/null

create_output="$(
  adb_cmd shell pm create-user     --profileOf 0     --managed     --for-testing     "Private Vault CI"
)"
WORK_USER="$(printf '%s\n' "$create_output" | sed -n 's/.*id \([0-9][0-9]*\).*/\1/p' | tail -n 1)"
if [[ -z "$WORK_USER" ]]; then
  echo "Unable to parse managed profile id from: $create_output" >&2
  exit 1
fi

adb_cmd shell pm install-existing --user "$WORK_USER" "$PACKAGE" >/dev/null

candidates=(
  "com.android.deskclock"
  "com.google.android.deskclock"
  "com.android.calculator2"
  "com.google.android.calculator"
  "com.android.contacts"
  "com.google.android.contacts"
  "com.android.settings"
)

for candidate in "${candidates[@]}"; do
  if ! adb_cmd shell pm path --user 0 "$candidate" 2>/dev/null | grep -q '^package:'; then
    continue
  fi

  uninstall_output="$(adb_cmd shell pm uninstall --user "$WORK_USER" "$candidate" 2>&1 || true)"
  if grep -q 'Success' <<<"$uninstall_output"; then
    SMOKE_PACKAGE="$candidate"
    break
  fi
done

if [[ -z "$SMOKE_PACKAGE" ]]; then
  echo "No suitable system app could be removed from the managed profile for clone smoke." >&2
  exit 1
fi

owner_output="$(adb_cmd shell dpm set-profile-owner --user "$WORK_USER" "$ADMIN" 2>&1)"
if ! grep -qi 'success' <<<"$owner_output"; then
  echo "Unable to set Private Vault as profile owner: $owner_output" >&2
  exit 1
fi

adb_cmd shell am start-user -w "$WORK_USER" >/dev/null
wait_for_profile_ready

TOKEN="private-vault-ci-${GITHUB_RUN_ID:-local}-${RANDOM}-$(date +%s)"
for user_id in 0 "$WORK_USER"; do
  bootstrap_output="$(
    adb_cmd shell am broadcast       --user "$user_id"       -n "$DEBUG_RECEIVER"       -a "$DEBUG_ACTION"       --es control_token "$TOKEN"
  )"
  if ! grep -q 'result=0' <<<"$bootstrap_output"; then
    echo "Debug work-profile bootstrap failed for user $user_id: $bootstrap_output" >&2
    exit 1
  fi
done

echo "Managed profile user: $WORK_USER"
echo "Clone smoke package: $SMOKE_PACKAGE"

flutter test   integration_test/work_profile_clone_smoke_test.dart   -d "$DEVICE"   --dart-define="WORK_PROFILE_SMOKE_PACKAGE=$SMOKE_PACKAGE"
