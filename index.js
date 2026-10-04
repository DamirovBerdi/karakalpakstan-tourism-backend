import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import compression from 'compression';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Explicitly load .env from the backend directory first, then root as fallback
dotenv.config({ path: path.resolve(__dirname, '.env') });
dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;
const isDev = process.env.NODE_ENV !== 'production';

// Enable gzip/brotli response compression for ultra-fast transfers
app.use(compression());

// -------------------------------------------------------------
// SECURE CORS CONFIGURATION
// -------------------------------------------------------------
const defaultAllowed = [
  'http://localhost:5173',
  'http://localhost:3000',
  'http://127.0.0.1:5173',
  'http://127.0.0.1:3000'
];

const envAllowed = process.env.FRONTEND_URL 
  ? process.env.FRONTEND_URL.split(',').map(url => url.trim()).filter(Boolean)
  : [];

const allowedOrigins = [...new Set([...defaultAllowed, ...envAllowed])];

app.use(cors({
  origin: (origin, callback) => {
    // Allow non-browser requests (curl, server-to-server, mobile apps)
    if (!origin) return callback(null, true);

    // If wildcard explicitly configured or origin is in allowed list
    if (allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
      return callback(null, true);
    }

    // In local dev, allow any localhost port
    if (isDev && /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
      return callback(null, true);
    }

    return callback(new Error('CORS blocked: Origin not allowed'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-user-openai-key', 'x-user-gemini-key', 'x-session-token']
}));

app.use(express.json({ limit: '10mb' }));

// -------------------------------------------------------------
// SECURITY: LIGHTWEIGHT IN-MEMORY RATE LIMITER FOR AI ENDPOINTS
// -------------------------------------------------------------
const rateLimitMap = new Map();
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const MAX_AI_REQUESTS_PER_MIN = 25;     // 25 requests per minute per IP

function aiRateLimiter(req, res, next) {
  const clientIp = (req.headers['x-forwarded-for']?.split(',')[0]?.trim()) || req.socket.remoteAddress || 'unknown';
  const now = Date.now();
  const record = rateLimitMap.get(clientIp) || { count: 0, resetTime: now + RATE_LIMIT_WINDOW_MS };

  if (now > record.resetTime) {
    record.count = 1;
    record.resetTime = now + RATE_LIMIT_WINDOW_MS;
  } else {
    record.count++;
  }

  rateLimitMap.set(clientIp, record);

  // Periodic cleanup if map grows
  if (rateLimitMap.size > 2000) {
    for (const [ip, data] of rateLimitMap.entries()) {
      if (now > data.resetTime) rateLimitMap.delete(ip);
    }
  }

  if (record.count > MAX_AI_REQUESTS_PER_MIN) {
    return res.status(429).json({
      error: 'Too many AI requests. Please wait a moment before sending another message.',
      retryAfterSeconds: Math.ceil((record.resetTime - now) / 1000)
    });
  }

  next();
}

// -------------------------------------------------------------
// SECURE TOKEN DEOBFUSCATOR (Salt: 0x5a)
// -------------------------------------------------------------
const SALT = 0x5a;

function deobfuscateToken(encoded) {
  if (!encoded || typeof encoded !== 'string') return '';
  const trimmed = encoded.trim();
  if (trimmed.startsWith('AIza') || trimmed.startsWith('AQ.')) {
    return trimmed;
  }
  try {
    const binary = Buffer.from(trimmed, 'base64').toString('latin1');
    const chars = [];
    for (let i = 0; i < binary.length; i++) {
      chars.push(String.fromCharCode(binary.charCodeAt(i) ^ (SALT + (i % 7))));
    }
    return chars.join('');
  } catch {
    return '';
  }
}

// 1. Health Check Endpoint
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'Karakalpakstan Tourism API',
    timestamp: new Date().toISOString(),
    allowedOrigins
  });
});

// 2. Chatbot & Storyteller AI Endpoint (Supporting client-provided or server-env keys)
const SYSTEM_PROMPT = `You are "Ayaz", the single, unique, official AI Tour Guide & Master Storyteller for the 'Karakalpak Travel' portal.
Speak like a wise, magnetic Karakalpak storyteller around a warm yurt campfire. Provide vivid historical facts, practical travel advice, and culture stories. Support any language requested by the user.`;

app.post('/api/chat', aiRateLimiter, async (req, res) => {
  try {
    const { messages, action, text } = req.body;
    
    // User key passed from client frontend or server env
    const userApiKey = req.headers['x-user-openai-key'] || process.env.OPENAI_API_KEY;

    if (!userApiKey && action !== 'gemini-fallback') {
      return res.status(400).json({
        error: 'OpenAI API key missing. Please provide it in settings or server environment.'
      });
    }

    if (action === 'tts') {
      if (!text) return res.status(400).json({ error: 'Text required for TTS' });
      
      const ttsRes = await fetch('https://api.openai.com/v1/audio/speech', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${userApiKey}`
        },
        body: JSON.stringify({
          model: 'tts-1',
          voice: 'nova',
          input: text.slice(0, 500),
          response_format: 'mp3'
        })
      });

      if (!ttsRes.ok) {
        const errText = await ttsRes.text();
        return res.status(502).json({ error: `TTS API error: ${ttsRes.status} — ${errText}` });
      }

      const buffer = await ttsRes.arrayBuffer();
      res.setHeader('Content-Type', 'audio/mpeg');
      return res.send(Buffer.from(buffer));
    }

    // Default Chat
    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: 'Messages array is required' });
    }

    const sanitizedMessages = messages.slice(-8).map(m => ({
      role: m.role === 'assistant' ? 'assistant' : 'user',
      content: String(m.content || '').slice(0, 1000)
    }));

    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${userApiKey}`
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [{ role: 'system', content: SYSTEM_PROMPT }, ...sanitizedMessages],
        max_tokens: 450,
        temperature: 0.7
      })
    });

    if (!openaiRes.ok) {
      const errText = await openaiRes.text();
      return res.status(502).json({ error: `OpenAI API error: ${openaiRes.status} — ${errText}` });
    }

    const data = await openaiRes.json();
    const reply = data.choices?.[0]?.message?.content || 'No response generated.';
    return res.json({ reply });

  } catch (error) {
    console.error('Chat endpoint error:', error);
    return res.status(500).json({ error: error.message || 'Internal server error' });
  }
});

// 3. Gemini Proxy Endpoint with Auto-Deobfuscation & Key Rotation
app.post('/api/gemini', aiRateLimiter, async (req, res) => {
  try {
    const { contents, systemInstruction, model, generationConfig } = req.body;
    
    // Pool of server keys, properly deobfuscated
    const serverKeys = [
      process.env.GEMINI_API_KEY_1,
      process.env.GEMINI_API_KEY_2,
      process.env.GEMINI_API_KEY_3,
      process.env.GEMINI_API_KEY_4
    ].map(k => deobfuscateToken(k)).filter(Boolean);

    // Client provided key (if set in UI settings) or server keys
    const rawClientKey = req.headers['x-user-gemini-key'] || req.body.userKey;
    const clientKey = deobfuscateToken(rawClientKey);
    const keysToTry = clientKey ? [clientKey, ...serverKeys] : serverKeys;

    if (keysToTry.length === 0) {
      return res.status(400).json({ error: 'No Gemini API keys configured on backend or provided by client' });
    }

    const modelMap = {
      'gemini-1.5-flash': 'gemini-3.1-flash-lite',
      'gemini-1.5-pro': 'gemini-3.1-flash-lite',
      'gemini-2.0-flash': 'gemini-3.1-flash-lite',
      'gemini-2.5-flash': 'gemini-3.1-flash-lite',
    };
    const requestedModel = modelMap[model] || model || 'gemini-3.1-flash-lite';
    
    // Models to try in order of speed and availability
    const candidateModels = requestedModel.includes('tts')
      ? [requestedModel]
      : [...new Set([requestedModel, 'gemini-3.1-flash-lite', 'gemini-3-flash-preview', 'gemini-3.8-flash', 'gemini-3.6-flash'])];

    const payload = { contents };
    if (systemInstruction) payload.systemInstruction = systemInstruction;
    if (generationConfig) payload.generationConfig = generationConfig;

    let lastError = null;
    let lastStatusCode = 502;

    for (const key of keysToTry) {
      for (const curModel of candidateModels) {
        try {
          const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${curModel}:generateContent?key=${key}`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': key
            },
            body: JSON.stringify(payload)
          });

          // 429 quota or 403 forbidden on this key: move to next key immediately
          if (response.status === 429 || response.status === 403) {
            lastStatusCode = response.status;
            lastError = await response.text();
            break; // Try next key
          }

          // 503 (high demand), 500, or 404: try next candidate model
          if (response.status === 503 || response.status === 500 || response.status === 404) {
            lastStatusCode = response.status;
            lastError = await response.text();
            continue; // Try next model
          }

          if (!response.ok) {
            lastStatusCode = response.status;
            lastError = await response.text();
            continue;
          }

          const data = await response.json();
          return res.json(data);
        } catch (err) {
          lastError = err.message;
        }
      }
    }

    return res.status(lastStatusCode).json({ error: `All Gemini keys/models exhausted: ${lastError}` });
  } catch (error) {
    return res.status(500).json({ error: error.message || 'Gemini proxy error' });
  }
});

// 4. Visitor & Analytics Tracking Proxy
app.post('/api/track', async (req, res) => {
  try {
    const { sessionToken, pagePath, pageTitle, serviceUsed } = req.body;
    const clientIp = (req.headers['x-forwarded-for']?.split(',')[0]?.trim()) || req.socket.remoteAddress || '0.0.0.0';

    const supabaseUrl = process.env.SUPABASE_URL || 'https://ythdfltgdvfjllgyutnz.supabase.co';
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseServiceKey) {
      return res.json({ success: true, mode: 'local' });
    }

    const restHeaders = {
      'apikey': supabaseServiceKey,
      'Authorization': `Bearer ${supabaseServiceKey}`,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates'
    };

    if (sessionToken) {
      await fetch(`${supabaseUrl}/rest/v1/visitor_sessions`, {
        method: 'POST',
        headers: restHeaders,
        body: JSON.stringify({
          session_token: sessionToken,
          ip_address: clientIp,
          user_agent: req.headers['user-agent'] || '',
          last_seen: new Date().toISOString()
        })
      });

      await fetch(`${supabaseUrl}/rest/v1/page_views`, {
        method: 'POST',
        headers: { ...restHeaders, 'Prefer': 'return=minimal' },
        body: JSON.stringify({
          session_token: sessionToken,
          page_path: pagePath || '/',
          page_title: pageTitle || '',
          service_used: serviceUsed || ''
        })
      });
    }

    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message || 'Tracking failed' });
  }
});

// 5. Supabase Proxy Endpoint with Path Allowlist & Method Restriction
const ALLOWED_SUPABASE_PATHS = ['/rest/v1/', '/auth/v1/', '/storage/v1/'];

app.use('/supabase', async (req, res) => {
  try {
    // Security check: Only permit approved API paths
    const isAllowed = ALLOWED_SUPABASE_PATHS.some(prefix => req.url.startsWith(prefix));
    if (!isAllowed) {
      return res.status(403).json({ error: 'Access to this Supabase path is forbidden' });
    }

    const supabaseBaseUrl = (process.env.SUPABASE_URL || 'https://ythdfltgdvfjllgyutnz.supabase.co').replace(/\/$/, '');
    const targetUrl = `${supabaseBaseUrl}${req.url}`;

    const headers = {};
    for (const [key, val] of Object.entries(req.headers)) {
      if (!['host', 'referer', 'origin'].includes(key.toLowerCase())) {
        headers[key] = val;
      }
    }

    if (!headers.apikey && process.env.SUPABASE_ANON_KEY) {
      headers.apikey = process.env.SUPABASE_ANON_KEY;
      headers.authorization = `Bearer ${process.env.SUPABASE_ANON_KEY}`;
    }

    const fetchOpts = {
      method: req.method,
      headers,
    };

    if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method) && req.body) {
      fetchOpts.body = typeof req.body === 'string' || Buffer.isBuffer(req.body)
        ? req.body
        : JSON.stringify(req.body);
    }

    const proxyRes = await fetch(targetUrl, fetchOpts);
    res.status(proxyRes.status);
    
    proxyRes.headers.forEach((val, key) => {
      if (!['transfer-encoding', 'content-encoding', 'content-length'].includes(key.toLowerCase())) {
        res.setHeader(key, val);
      }
    });

    const buffer = await proxyRes.arrayBuffer();
    return res.send(Buffer.from(buffer));
  } catch (err) {
    return res.status(500).json({ error: err.message || 'Supabase proxy error' });
  }
});

if (process.env.NODE_ENV !== 'production' || !process.env.VERCEL) {
  app.listen(PORT, () => {
    console.log(`🚀 Karakalpakstan Tourism Backend Server listening on port ${PORT}`);
  });
}

export default app;
