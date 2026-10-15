// Parse a llama-server chat response and print timing facts.
import fs from 'node:fs';
const f = process.argv[2];
const j = JSON.parse(fs.readFileSync(f, 'utf8'));
if (j.error) { console.log('ERROR ' + JSON.stringify(j.error)); process.exit(0); }
const t = j.timings || {};
console.log(`prompt_n=${t.prompt_n} gen_n=${t.predicted_n} prompt_tps=${(+t.prompt_per_second).toFixed(1)} gen_tps=${(+t.predicted_per_second).toFixed(2)} total_s=${((t.prompt_ms + t.predicted_ms) / 1000).toFixed(1)}`);
console.log('text=' + (j.choices?.[0]?.message?.content || '').replace(/\s+/g, ' ').slice(0, 80));
