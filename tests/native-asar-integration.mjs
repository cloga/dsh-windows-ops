// Explicit external REAL-runtime qualification entry. Not part of synthetic unit
// tests; missing input is a FAILURE, never a skip or a claimed .6 acceptance.
import { readFileSync, statSync } from 'node:fs';
import { verifyNativeDesktopFiles } from '../tools/verify-native-desktop.mjs';
import { nativeLayout } from '../tools/native-asar-runtime.mjs';
import { requireValue, safeReason } from '../tools/native-runtime-integrity.mjs';
try {
  requireValue(process.argv.length === 3, 'native-real-fixture-required');
  requireValue(statSync(process.argv[2]).size <= 1024 * 1024, 'native-probe-input-limit');
  const input = JSON.parse(readFileSync(process.argv[2], 'utf8').replace(/^\uFEFF/u, ''));
  requireValue(input.fixtureKind === 'external-real-runtime' && nativeLayout(input.lock) === 'asar-runtime' &&
    typeof input.diagnosticRoot === 'string', 'native-real-fixture-required');
  const result = verifyNativeDesktopFiles(input);
  requireValue(result.valid && result.runtime.mode === 'asar-runtime' && result.runtime.sharedPeerResolution === 'metadata-cjs-esm' &&
    result.provisioning.sharedPeerResolution === 'host-owned', result.runtime.reason ?? result.provisioning.reason ?? 'native-real-fixture-failed');
  process.stdout.write(JSON.stringify({ valid: true, qualification: 'external-real-runtime-files-and-resolution',
    runtime: result.runtime, modelResponseVerified: false, formalReleaseAcceptance: false }) + '\n');
} catch (error) {
  process.stdout.write(JSON.stringify({ valid: false, qualification: 'not-ready', reason: safeReason(error),
    modelResponseVerified: false, formalReleaseAcceptance: false }) + '\n');
  process.exitCode = 1;
}
