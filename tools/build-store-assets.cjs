const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
(async () => {
  const root = path.resolve(__dirname, '..');
  const folder = path.join(root, 'store', 'Assets');
  fs.mkdirSync(folder, { recursive: true });
  for (const [name, size] of [['StoreLogo', 50], ['Square44x44Logo', 44], ['Square150x150Logo', 150]]) {
    await sharp(path.join(root, 'docs', 'icon.svg'), { density: 384 }).resize(size, size).png().toFile(path.join(folder, name + '.png'));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
