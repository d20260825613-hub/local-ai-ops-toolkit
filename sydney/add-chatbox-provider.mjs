// Add the local Sydney (New Bing 复刻) provider to Chatbox's config.json.
// Idempotent. Run only while Chatbox is closed.
import fs from 'node:fs';

const CFG = `${process.env.APPDATA}\\xyz.chatboxapp.app\\config.json`;
const PROVIDER_ID = 'custom-sydney';
const HOST = 'http://127.0.0.1:8081/v1';
const MODEL = 'sydney-9b';

const raw = fs.readFileSync(CFG, 'utf8').replace(/^\ufeff/, '');
const cfg = JSON.parse(raw);
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
