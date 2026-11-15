// Walidacja plików GLB oficjalnym walidatorem Khronos (npm: gltf-validator).
// Użycie: node tools/validate_gltf.js plik1.glb [plik2.glb ...]  → JSON z podsumowaniem na stdout
const fs = require('fs');
const path = require('path');
const validator = require('gltf-validator');

async function run(file) {
  const asset = new Uint8Array(fs.readFileSync(file));
  const report = await validator.validateBytes(asset, {
    uri: file,
    externalResourceFunction: (uri) => new Promise((resolve, reject) => {
      const p = path.resolve(path.dirname(file), decodeURIComponent(uri));
      fs.readFile(p, (err, data) => err ? reject(err.toString()) : resolve(new Uint8Array(data)));
    }),
  });
  return {
    file,
    errors: report.issues.numErrors,
    warnings: report.issues.numWarnings,
    infos: report.issues.numInfos,
    messages: report.issues.messages.filter(m => m.severity <= 1).map(m => `${m.severity === 0 ? 'E' : 'W'} ${m.code} ${m.pointer || ''} ${m.message}`),
  };
}

(async () => {
  const out = [];
  for (const f of process.argv.slice(2)) out.push(await run(f));
  console.log(JSON.stringify(out, null, 1));
  process.exit(out.some(r => r.errors > 0) ? 1 : 0);
})();
