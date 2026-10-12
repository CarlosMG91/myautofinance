import {readFileSync, writeFileSync} from 'node:fs';
const root = new URL('./', import.meta.url);
const tokens = JSON.parse(readFileSync(new URL('tokens-visuales.json', root), 'utf8'));
const kebab = key => key.replace(/[A-Z]/g, c => `-${c.toLowerCase()}`);
const lines = ['/* Generado desde tokens-visuales.json. Ejecutar node generar-tokens.mjs. */', ':root {'];
for (const [key, value] of Object.entries(tokens.color)) lines.push(`  --${kebab(key)}: ${value};`);
for (const [key, value] of Object.entries(tokens.space)) lines.push(`  --space-${key}: ${value}px;`);
for (const [key, value] of Object.entries(tokens.radius)) lines.push(`  --radius-${key}: ${value}px;`);
for (const [key, value] of Object.entries(tokens.type)) {
  if (typeof value !== 'object') continue;
  lines.push(`  --type-${key}: ${value.size / 16}rem;`);
  lines.push(`  --weight-${key}: ${value.weight};`);
  lines.push(`  --line-${key}: ${value.lineHeight};`);
}
lines.push('}', '');
const css = lines.join('\n');
const file = new URL('tokens.css', root);
if (process.argv.includes('--check')) {
  if (readFileSync(file, 'utf8') !== css) throw Error('tokens.css desactualizado');
  console.log('Tokens CSS coinciden con JSON.');
} else writeFileSync(file, css);
