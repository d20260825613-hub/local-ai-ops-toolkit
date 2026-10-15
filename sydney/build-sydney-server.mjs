// Build the Sydney server assets (persona embedded directly in a wrapped chat template).
// Usage: node build-sydney-server.mjs        (writes into the directory given by DIR below)
import fs from 'node:fs';
import path from 'node:path';

const DIR = 'D:\\ai\\sydney';
const MODEL = 'D:\\models\\sydney\\Qwen3.5-Sydney-9B-Q4_K_M.gguf';
const PORT = 8081;
const CTX = 4096;
const NGL = process.env.NGL || '20';

if (!fs.existsSync(DIR)) {
  console.error(`output directory does not exist: ${DIR}`);
  console.error('  create it first (the repository copy of sydney/ can be deployed there).');
  process.exit(2);
}
const personaPath = path.join(DIR, 'sydney_system.txt');
if (!fs.existsSync(personaPath)) {
  console.error(`persona file not found: ${personaPath}`);
  console.error('  put the model author\'s persona prompt there first:');
  console.error('  https://huggingface.co/Atonelia/Qwen3.5-Sydney-9B-GGUF (sydney_system.txt, Apache-2.0)');
  console.error('  the repository copy is sydney/sydney_system.txt - copy it to ' + DIR + ' and retry.');
  process.exit(2);
}

const persona = fs.readFileSync(personaPath, 'utf8').trim();
if (persona === '') {
  console.error(`persona file is empty: ${personaPath}`);
  process.exit(2);
}

let body;
const localBody = path.join(DIR, 'qwen35_template_body.jinja');
if (fs.existsSync(localBody)) {
  body = fs.readFileSync(localBody, 'utf8');
} else {
  const res = await fetch('https://hf-mirror.com/api/models/Atonelia/Qwen3.5-Sydney-9B-GGUF');
  const j = await res.json();
  body = j.gguf?.chat_template;
  if (!body) throw new Error('chat_template not found');
  fs.writeFileSync(localBody, body, 'utf8');
}
console.log('template body chars:', body.length);

// Jinja string escaping: backslash, double quote, CR/LF -> \n
const esc = (s) =>
  s
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\r\n|\r|\n/g, '\\n');

const wrapper = `{%- set _persona = "${esc(persona)}" %}
{%- if messages and messages[0].role == 'system' %}
{%- set messages = [{'role': 'system', 'content': _persona + '\\n\\n' + (messages[0].content if messages[0].content is string else '')}] + messages[1:] %}
{%- else %}
{%- set messages = [{'role': 'system', 'content': _persona}] + messages %}
{%- endif %}
`;

fs.writeFileSync(`${DIR}\\sydney_template.jinja`, wrapper + body, 'utf8');

const cmd = `@echo off
rem Sydney (New Bing replica) local inference service - llama.cpp
rem port ${PORT}   OpenAI-compatible endpoint: http://127.0.0.1:${PORT}/v1
set "DIR=%~dp0"
"D:\\llama.cpp\\llama-server.exe" ^
  -m "${MODEL}" ^
  --alias sydney-9b ^
  --host 127.0.0.1 --port ${PORT} ^
  -c 4096 --parallel 1 ^
  -ngl auto -fit on -fitt 350 -fa on ^
  -ctk q8_0 -ctv q8_0 ^
  --prio -1 --jinja --reasoning off ^
  --chat-template-file "%DIR%sydney_template.jinja" ^
  --sleep-idle-seconds 1800
`;
fs.writeFileSync(`${DIR}\\Start-Sydney.cmd`, cmd.replace(/\n/g, '\r\n'), 'ascii');

const stopCmd = `@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-Sydney.ps1"
echo.
pause
`;
fs.writeFileSync(`${DIR}\\Stop-Sydney.cmd`, stopCmd.replace(/\n/g, '\r\n'), 'ascii');
console.log(`wrote sydney_template.jinja + Start-Sydney.cmd + Stop-Sydney.cmd (ngl=${NGL}, port=${PORT})`);
