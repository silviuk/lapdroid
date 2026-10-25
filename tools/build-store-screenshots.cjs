// Assemble real Windows captures. Only the paired-device name/address is redacted.
// Inputs are local captures of the published release, never fabricated UI.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const crypto = require('node:crypto');
(async () => {
  const root = path.resolve(__dirname, '..');
  const folder = path.join(root, 'store', 'Screenshots');
  fs.mkdirSync(folder, { recursive: true });
  const entries = [
    {name:'controls',title:'Your laptop. Your phone.',lines:['Connect over Bluetooth.','Type, tap and scroll.','Release capture with F12.'],description:'Windows controls for Bluetooth connection, input capture, sensitivity and Android actions. Paired device details are hidden.'},
    {name:'diagnostics',title:'Connection diagnostics.',lines:['Inspect activity in one place.','Copy logs when you need help.','Review private details first.'],description:'Activity & Logs controls with an empty diagnostic buffer after clearing the test session.'}
  ];
  const screenshots=[];
  for (const item of entries) {
    let app = sharp(path.join(root,'.build',item.name==='controls'?'controls-raw.png':'logs-raw.png'));
    const meta = await app.metadata();
    if(meta.width!==556 || meta.height!==708) throw new Error('Unexpected capture dimensions; inspect before changing redaction bounds.');
    if(item.name==='controls') {
      const redaction=Buffer.from('<svg width="330" height="20"><rect width="330" height="20" fill="#f5f5f5"/><text x="4" y="14" font-family="Segoe UI" font-size="12" fill="#666">Paired device details hidden for privacy</text></svg>');
      app=app.composite([{input:redaction,left:37,top:215}]);
    }
    const capture=await app.png().toBuffer();
    const text = item.lines.map((line,i)=>`<text x="80" y="${340+i*40}" font-family="Segoe UI" font-size="23" fill="#4b5d69">${line}</text>`).join('');
    const backdrop=Buffer.from(`<svg width="1440" height="1000"><rect width="1440" height="1000" fill="#eef4f5"/><text x="80" y="200" font-family="Segoe UI" font-size="23" font-weight="600" fill="#17676b">LAPDROID · WINDOWS + ANDROID</text><text x="80" y="270" font-family="Segoe UI" font-size="34" font-weight="700" fill="#172f3c">${item.title}</text>${text}<text x="80" y="850" font-family="Segoe UI" font-size="17" fill="#4b5d69">Requires the separate Android companion,</text><text x="80" y="878" font-family="Segoe UI" font-size="17" fill="#4b5d69">Bluetooth and Android permissions.</text></svg>`);
    const fileName=item.name+'.png';
    const output=await sharp(backdrop).composite([{input:capture,left:790,top:145}]).png().toBuffer();
    fs.writeFileSync(path.join(folder,fileName),output);
    screenshots.push({fileName,description:item.description,sha256:crypto.createHash('sha256').update(output).digest('hex')});
  }
  fs.writeFileSync(path.join(folder,'screenshots.json'),JSON.stringify({version:'0.3.0',language:'en-us',screenshots},null,2)+'\n');
})().catch(e=>{console.error(e);process.exitCode=1});
