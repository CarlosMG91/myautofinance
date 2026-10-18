// Compiler smoke test only. Deliberately invalid application PE: AfInitialize
// rejects it. This cannot be mistaken for a production/clean-profile test.
import { resolve } from 'node:path';
import { mkdirSync, writeFileSync } from 'node:fs';
import { writePackage } from '../windows-installer.mjs';
import { inventory } from '../windows-payload.mjs';
const [bridge, destination] = process.argv.slice(2);
if (!bridge || !destination) throw new Error('bridge and fresh fixture directory required');
const payload = resolve(destination, 'synthetic-payload');
mkdirSync(payload, { recursive: true });
writeFileSync(resolve(payload, 'myautofinance.exe'), 'SYNTHETIC COMPILER FIXTURE - NOT AN APPLICATION');
writeFileSync(resolve(destination, 'NOT-A-DELIVERY.txt'), 'Only validates Inno compilation. Never run/distribute this fixture installer. No production payload, no native installation acceptance.\n');
writePackage({ payload, files: inventory(payload), bridge, output: resolve(destination, 'output'), version: { applicationVersion: '0.1.0+1', windowsVersion: '0.1.0.1' } });
