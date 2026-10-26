import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const project = fileURLToPath(new URL('..', import.meta.url));
const lock = JSON.parse(await readFile(join(project, 'package-lock.json'), 'utf8'));
const allowedDependencies = new Set(['MIT', 'Apache-2.0']);
const localLicense = 'UPL-1.0';
const localPackages = new Set(['picocolors', 'source-map-js']);
const rejected = [];
let checked = 0;

for (const [path, metadata] of Object.entries(lock.packages)) {
  if (!path.startsWith('node_modules/') || path.includes('/vendor/')) continue;
  let license = metadata.license;
  if (metadata.link) {
    const pkg = JSON.parse(await readFile(join(project, path, 'package.json'), 'utf8'));
    license = pkg.license;
  }
  const expectedLocal = metadata.link && localPackages.has(path.slice('node_modules/'.length));
  if (!expectedLocal) checked++;
  if (expectedLocal ? license !== localLicense : !allowedDependencies.has(license)) {
    rejected.push(`${path}: ${license ?? 'licenza non dichiarata'}`);
  }
}

for (const name of localPackages) {
  const pkg = JSON.parse(await readFile(join(project, 'vendor', name, 'package.json'), 'utf8'));
  if (pkg.license !== localLicense) rejected.push(`vendor/${name}: ${pkg.license ?? 'licenza non dichiarata'}`);
  if (lock.packages[`vendor/${name}`]?.license !== localLicense) rejected.push(`package-lock.json vendor/${name}: licenza non allineata`);
}

if (rejected.length) {
  console.error('Licenze non conformi (dipendenze MIT / Apache-2.0, moduli locali UPL-1.0):\n' + rejected.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`${checked} dipendenze MIT o Apache-2.0; due moduli locali UPL-1.0.`);
}
