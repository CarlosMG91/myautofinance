import { mkdirSync, copyFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { writePackage } from '../windows-installer.mjs';
import { inventory } from '../windows-payload.mjs';
const [bridge, exe, destination, revision] = process.argv.slice(2);
if (!bridge || !exe || !destination || !['1', '2'].includes(revision)) throw new Error('Synthetic fixture parameters required');
const payload = resolve(destination, 'synthetic-payload');
mkdirSync(payload, { recursive: true });
copyFileSync(exe, resolve(payload, 'myautofinance.exe'));
writeFileSync(resolve(payload, 'NOT-A-DELIVERY.txt'), 'Synthetic CI fixture. Not Autofinance. Never distribute.\n');
writePackage({ payload, files: inventory(payload), bridge, output: resolve(destination, 'output'),
  version: { applicationVersion: `0.0.0+${revision}`, windowsVersion: `0.0.0.${revision}` } });
