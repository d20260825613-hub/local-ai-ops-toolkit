// Parse a llama-server chat response and print timing facts.
// Usage: node parse-timings.mjs <response.json>
import fs from 'node:fs';

const f = process.argv[2];
if (!f) {
  console.error('usage: node parse-timings.mjs <response.json>');
  console.error('  e.g. node parse-timings.mjs final_resp.json');
  console.error('  (a JSON file you saved from a llama-server /v1/chat/completions call)');
  process.exit(2);
}
if (!fs.existsSync(f)) {
  console.error(`input file not found: ${f}`);
  console.error('  save the full JSON response body to a file first, then pass its path.');
  process.exit(2);
}
if (fs.statSync(f).size === 0) {
  console.error(`input file is empty: ${f}`);
  console.error('  it looks like the response was never written (curl -o / tee failed?).');
  process.exit(2);
}

let j;
try {
  j = JSON.parse(fs.readFileSync(f, 'utf8'));
} catch (e) {
  console.error(`not valid JSON: ${f} (${e.message})`);
  console.error('  pass the raw response body, not the server log.');
  process.exit(2);
}

if (j.error) { console.log('ERROR ' + JSON.stringify(j.error)); process.exit(0); }
const t = j.timings || {};
if (Object.keys(t).length === 0) {
  console.error('no "timings" field in the response');
  console.error('  start llama-server with --timings (or use a build that reports timings).');
  process.exit(3);
}
console.log(`prompt_n=${t.prompt_n} gen_n=${t.predicted_n} prompt_tps=${(+t.prompt_per_second).toFixed(1)} gen_tps=${(+t.predicted_per_second).toFixed(2)} total_s=${((t.prompt_ms + t.predicted_ms) / 1000).toFixed(1)}`);
console.log('text=' + (j.choices?.[0]?.message?.content || '').replace(/\s+/g, ' ').slice(0, 80));
