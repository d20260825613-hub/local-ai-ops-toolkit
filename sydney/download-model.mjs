// Parallel (multi-connection) downloader with resume + SHA-256 verification.
// All work on D: per user preference.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pipeline } from 'node:stream/promises';

const URL_ = 'https://hf-mirror.com/Atonelia/Qwen3.5-Sydney-9B-GGUF/resolve/main/Qwen3.5-Sydney-9B-Q4_K_M.gguf';
const OUT = 'D:\\models\\sydney\\Qwen3.5-Sydney-9B-Q4_K_M.gguf';
const PARTS_DIR = 'D:\\models\\sydney\\parts';
const TOTAL = 5629108448;
const SHA256 = 'bfb1d7336be62acd7e6d2f4429cd8ad1039406c6a26da6a8343bbbac70e29933';
const NPARTS = Number(process.env.NPARTS || 8);
const MAX_TRIES = 12;

fs.mkdirSync(PARTS_DIR, { recursive: true });

const chunk = Math.ceil(TOTAL / NPARTS);
const parts = [];
for (let i = 0; i < NPARTS; i++) {
  const start = i * chunk;
  const end = Math.min(TOTAL, start + chunk) - 1;
  if (start > end) break;
  parts.push({ i, start, end, file: path.join(PARTS_DIR, `part-${String(i).padStart(2, '0')}.bin`) });
}

let lastBytes = parts.reduce((a, p) => a + (fs.existsSync(p.file) ? fs.statSync(p.file).size : 0), 0);
const prog = setInterval(() => {
  const now = parts.reduce((a, p) => a + (fs.existsSync(p.file) ? fs.statSync(p.file).size : 0), 0);
  const done = ((now / TOTAL) * 100).toFixed(1);
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${(now / 1048576).toFixed(0)}MB / ${(TOTAL / 1048576).toFixed(0)}MB (${done}%)  +${((now - lastBytes) / 1048576 / 5).toFixed(2)} MB/s`);
  lastBytes = now;
}, 5000);

async function fetchPart(p) {
  const want = p.end - p.start + 1;
  for (let attempt = 1; attempt <= MAX_TRIES; attempt++) {
    const have = fs.existsSync(p.file) ? fs.statSync(p.file).size : 0;
    if (have >= want) return;
    const from = p.start + have;
    try {
      const res = await fetch(URL_, { headers: { Range: `bytes=${from}-${p.end}` } });
      if (!res.ok && res.status !== 206) throw new Error(`HTTP ${res.status}`);
      await pipeline(res.body, fs.createWriteStream(p.file, { flags: have ? 'a' : 'w' }));
      const after = fs.statSync(p.file).size;
      if (after >= want) return;
      console.log(`part ${p.i}: incomplete ${after}/${want} (attempt ${attempt}), retrying`);
    } catch (e) {
      console.log(`part ${p.i}: attempt ${attempt} failed: ${e.message}`);
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
  throw new Error(`part ${p.i} failed after ${MAX_TRIES} attempts`);
}

try {
  await Promise.all(parts.map(fetchPart));
  clearInterval(prog);

  for (const p of parts) {
    const want = p.end - p.start + 1;
    const got = fs.statSync(p.file).size;
    if (got !== want) throw new Error(`part ${p.i} size mismatch: ${got} != ${want}`);
  }
  console.log('all parts complete, concatenating...');
  const out = fs.createWriteStream(OUT);
  for (const p of parts) {
    await pipeline(fs.createReadStream(p.file), out, { end: false });
  }
  await new Promise((r) => out.end(r));

  const size = fs.statSync(OUT).size;
  console.log(`output size: ${size} (expected ${TOTAL})`);
  if (size !== TOTAL) throw new Error('final size mismatch');
  const hash = crypto.createHash('sha256');
  await pipeline(fs.createReadStream(OUT), hash);
  const got = hash.digest('hex');
  console.log(`sha256: ${got}`);
  console.log(got === SHA256 ? 'SHA256 OK' : 'SHA256 MISMATCH');
  if (got !== SHA256) process.exitCode = 2;
  else {
    for (const p of parts) fs.rmSync(p.file, { force: true });
    fs.rmdirSync(PARTS_DIR);
    console.log('cleanup done');
  }
} catch (e) {
  clearInterval(prog);
  console.error('FAILED:', e.message);
  process.exitCode = 1;
}
