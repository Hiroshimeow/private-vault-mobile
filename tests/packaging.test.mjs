import { readFileSync, existsSync } from 'node:fs';
import vm from 'node:vm';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const config = JSON.parse(read('capacitor.config.json'));

test('APK uses a bundled secure origin and a separate application identity', () => {
  assert.equal(config.webDir, 'dist');
  assert.equal(config.appId, 'me.hculab.privatevault.web');
  assert.equal(config.android.path, 'android-capacitor');
  assert.equal(config.server.androidScheme, 'https');
  assert.equal(config.server.url, undefined);
  assert.equal(config.server.allowNavigation, undefined);
  assert.equal(config.android.allowMixedContent, false);
  assert.equal(config.android.webContentsDebuggingEnabled, false);
});

test('Android rejects backup, cleartext and unguarded production signing', () => {
  const manifest = read('android-capacitor/app/src/main/AndroidManifest.xml');
  assert.match(manifest, /android:allowBackup="false"/);
  assert.match(manifest, /android:usesCleartextTraffic="false"/);
  assert.match(manifest, /android:dataExtractionRules="@xml\/data_extraction_rules"/);
  const gradle = read('android-capacitor/app/build.gradle');
  assert.match(gradle, /Production signing credentials are required/);
  assert.doesNotMatch(gradle, /signingConfig\s+signingConfigs\.debug/);
  assert.match(read('android-capacitor/app/src/main/java/me/hculab/privatevault/web/MainActivity.java'), /FLAG_SECURE/);
});

test('release publication depends on actual CI and emulator evidence', () => {
  const release = read('.github/workflows/release-rc.yml');
  assert.match(release, /needs: verify/);
  assert.match(release, /--verify-tag --prerelease/);
  assert.match(release, /SHA256SUMS/);
  assert.match(release, /android-smoke-evidence/);
  assert.match(read('.github/workflows/ci.yml'), /uses: .\/\.github\/workflows\/android-integration.yml/);
  assert.doesNotMatch(read('.github/workflows/ci.yml'), /hashFiles\(/);
  assert.ok(existsSync(new URL('../package-lock.json', import.meta.url)));
});

function controllerClass() {
  const code = ts.transpileModule(read('src/features/auth/lockController.ts'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  const sandbox = { exports: {}, setTimeout, clearTimeout };
  vm.runInNewContext(code, sandbox);
  return sandbox.exports.LockController;
}

test('cold start is locked; unlock is explicit; background and panic relock', () => {
  const Controller = controllerClass();
  const controller = new Controller();
  assert.equal(controller.isLocked, true);
  controller.unlock();
  assert.equal(controller.isLocked, false);
  controller.onBackground(0);
  assert.equal(controller.isLocked, true);
  controller.unlock();
  controller.panic();
  assert.equal(controller.isLocked, true);
  controller.dispose();
});

test('foreground cancels the configured web background delay', async () => {
  const Controller = controllerClass();
  const controller = new Controller();
  controller.unlock();
  controller.onBackground(20);
  controller.onForeground();
  await new Promise((resolve) => setTimeout(resolve, 40));
  assert.equal(controller.isLocked, false);
  controller.dispose();
});
