#!/usr/bin/env bash
set -euo pipefail
adb install -r artifacts/Private-Vault-1.0.0-DEBUG-TEST-ONLY.apk
adb install -r artifacts/app-debug-androidTest.apk
adb shell am instrument -w -r me.hculab.privatevault.web.test/androidx.test.runner.AndroidJUnitRunner | tee android-smoke.txt
grep -Eq '^OK \([1-9][0-9]* tests?\)' android-smoke.txt
if grep -Eq 'FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed' android-smoke.txt; then
  exit 1
fi
