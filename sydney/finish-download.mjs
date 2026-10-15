// Finish the last incomplete part with parallel sub-ranges, then concat + verify SHA-256.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const URL_ = 'https://hf-mirror.com/Atonelia/Qwen3.5-Sydney-9B-GGUF/resolve/main/Qwen3.5-Sydney-9B-Q4_K_M.gguf';
const OUT = 'D:\\models\\sydney\\Qwen3.5-Sydney-9B-Q4_K_M.gguf';
const PARTS_DIR = 'D:\\models\\sydney\\parts';
const TOTAL = 5629108448;
const SHA256 = 'bfb1d7336be62acd7e6d2f4429cd8ad1039406c6a26da6a8343bbbac70e29933';
const NPARTS = 8;
const SUB = 6; // parallel sub-ranges for the remaining piece

const chunk = Math.ceil(TOTAL / NPARTS);
const parts = [];
for (let i = 0; i < NPARTS; i++) {
  const start = i * chunk;
  const end = Math.min(TOTAL, start + chunk) - 1;
  if (start > end) break;
  parts.push({ i, start, end, file: path.join(PARTS_DIR, `part-${String(i).padStart(2, '0')}.bin`) });
}

async function getRange(url, from, to, file) {
  const have = fs.existsSync(file) ? fs.statSync(file).size : 0;
  if (have >= to - from + 1) return;
  const res = await fetch(url, { headers: { Range: `bytes=${from + have}-${to}` } });
  if (!res.ok && res.status !== 206) throw new Error(`HTTP ${res.status}`);
  const ws = fs.createWriteStream(file, { flags: have ? 'a' : 'w' });
  for await (const b of res.body) {
    if (!ws.write(b)) await new Promise((r) => ws.once('drain', r));
  }
  await new Promise((r) => ws.end(r));
}

const prog = setInterval(() => {
  const now = parts.reduce((a, p) => a + (fs.existsSync(p.file) ? fs.statSync(p.file).size : 0), 0);
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${(now / 1048576).toFixed(0)}MB / ${(TOTAL / 1048576).toFixed(0)}MB (${((now / TOTAL) * 100).toFixed(1)}%)`);
}, 5000);

try {
  // finish incomplete parts with parallel sub-ranges
  for (const p of parts) {
    const want = p.end - p.start + 1;
    const have = fs.existsSync(p.file) ? fs.statSync(p.file).size : 0;
    if (have >= want) continue;
    const from = p.start + have;
    const remain = p.end - from + 1;
    const sub = Math.min(SUB, Math.max(1, Math.ceil(remain / 32_000_000)));
    const size = Math.ceil(remain / sub);
    console.log(`part ${p.i}: ${(have / 1048576).toFixed(0)}MB done, finishing ${(remain / 1048576).toFixed(0)}MB in ${sub} sub-ranges`);
    const temps = [];
    for (let s = 0; s < sub; s++) {
      const sFrom = from + s * size;
      const sTo = Math.min(p.end, sFrom + size - 1);
      if (sFrom > sTo) break;
      temps.push({ from: sFrom, to: sTo, file: `${p.file}.sub${s}` });
    }
    await Promise.all(temps.map(async (t) => {
      for (let attempt = 1; attempt <= 8; attempt++) {
        try { await getRange(URL_, t.from, t.to, t.file); break; }
        catch (e) { console.log(`sub ${t.file} attempt ${attempt}: ${e.message}`); await new Promise((r) => setTimeout(r, 2000)); }
        if (attempt === 8) throw new Error(`sub-range failed: ${t.file}`);
      }
    }));
    for (const t of temps) {
      const buf = fs.readFileSync(t.file); // <= ~32MB pieces
      fs.appendFileSync(p.file, buf);
      fs.rmSync(t.file, { force: true });
    }
  }

  clearInterval(prog);
  for (const p of parts) {
    const want = p.end - p.start + 1;
    const got = fs.statSync(p.file).size;
    if (got !== want) throw new Error(`part ${p.i} size mismatch: ${got} != ${want}`);
  }
  console.log('all parts complete, concatenating...');
  const out = fs.createWriteStream(OUT);
  for (const p of parts) {
    await new Promise((resolve, reject) => {
      const rs = fs.createReadStream(p.file);
      rs.on('error', reject);
      rs.on('end', resolve);
      rs.pipe(out, { end: false });
    });
  }
  await new Promise((r) => out.end(r));
  const size = fs.statSync(OUT).size;
  console.log('output size:', size, 'expected', TOTAL);
  const hash = crypto.createHash('sha256');
  await new Promise((resolve, reject) => {
    const rs = fs.createReadStream(OUT);
    rs.on('error', reject);
    rs.on('data', (d) => hash.update(d));
    rs.on('end', resolve);
  });
  const got = hash.digest('hex');
  console.log('sha256:', got, got === SHA256 ? 'OK' : 'MISMATCH');
  if (got !== SHA256) process.exitCode = 2;
  else {
    for (const p of parts) fs.rmSync(p.file, { force: true });
    console.log('cleanup done');
  }
} catch (e) {
  clearInterval(prog);
  console.error('FAILED:', e.message);
  process.exitCode = 1;
}
