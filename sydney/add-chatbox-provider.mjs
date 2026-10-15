// Add the local Sydney (New Bing 复刻) provider to Chatbox's config.json.
// Idempotent. Run only while Chatbox is closed.
import fs from 'node:fs';

const CFG = `${process.env.APPDATA}\\xyz.chatboxapp.app\\config.json`;
const PROVIDER_ID = 'custom-sydney';
const HOST = 'http://127.0.0.1:8081/v1';
const MODEL = 'sydney-9b';

if (!process.env.APPDATA) {
  console.error('APPDATA is not set; cannot locate the Chatbox config directory.');
  process.exit(2);
}
if (!fs.existsSync(CFG)) {
  console.error(`Chatbox config not found: ${CFG}`);
  console.error('  is Chatbox installed for this Windows user? (it writes xyz.chatboxapp.app under %APPDATA%)');
  process.exit(2);
}

const raw = fs.readFileSync(CFG, 'utf8').replace(/^\ufeff/, '');
if (raw.trim() === '') {
  console.error(`Chatbox config is empty: ${CFG}`);
  console.error('  start Chatbox once so it writes its config, then close it and retry.');
  process.exit(2);
}
let cfg;
try {
  cfg = JSON.parse(raw);
} catch (e) {
  console.error(`Chatbox config is not valid JSON: ${CFG} (${e.message})`);
  console.error('  close Chatbox completely (also the tray icon) and retry; nothing was written.');
  process.exit(2);
}
if (cfg === null || typeof cfg !== 'object' || Array.isArray(cfg)) {
  console.error(`Chatbox config has an unexpected shape (${Array.isArray(cfg) ? 'array' : typeof cfg}): ${CFG}`);
  process.exit(2);
}

// back up before the first change to this file
const backup = `${CFG}.bak-before-sydney`;
if (!fs.existsSync(backup)) {
  try {
    fs.copyFileSync(CFG, backup);
    console.log('backup written:', backup);
  } catch (e) {
    console.error(`could not write the backup ${backup}: ${e.message}`);
    process.exit(2);
  }
}

const s = cfg.settings ?? (cfg.settings = {});

s.customProviders = Array.isArray(s.customProviders) ? s.customProviders : [];
s.customProviders = s.customProviders.filter((p) => p.id !== PROVIDER_ID);
s.customProviders.push({
  id: PROVIDER_ID,
  name: 'Sydney (New Bing 复刻)',
  type: 'openai',
  isCustom: true,
  defaultSettings: { apiHost: HOST },
});

s.providers = s.providers ?? {};
s.providers[PROVIDER_ID] = {
  apiKey: 'sk-local',
  apiHost: HOST,
  models: [
    {
      modelId: MODEL,
      type: 'chat',
      apiStyle: 'openai',
      nickname: 'Sydney 9B (New Bing 复刻)',
      capabilities: ['tool_use'],
      contextWindow: 4096,
      maxOutput: 1024,
    },
  ],
};

fs.writeFileSync(CFG, JSON.stringify(cfg, null, '\t'), 'utf8');
console.log('custom providers:', s.customProviders.map((p) => p.id).join(', '));
console.log('provider keys:', Object.keys(s.providers).join(', '));
console.log('sydney model:', s.providers[PROVIDER_ID].models[0].modelId, '@', s.providers[PROVIDER_ID].apiHost);
