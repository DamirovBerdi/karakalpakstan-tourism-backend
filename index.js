import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Enable CORS for frontend connection
const allowedOrigins = process.env.FRONTEND_URL 
  ? process.env.FRONTEND_URL.split(',').map(url => url.trim()) 
  : ['http://localhost:5173', 'http://localhost:3000'];

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(null, true); // Allow all in dev mode for flexibility
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-user-openai-key', 'x-user-gemini-key', 'x-session-token']
}));

app.use(express.json({ limit: '10mb' }));

// 1. Health Check Endpoint
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'Karakalpakstan Tourism API',
    timestamp: new Date().toISOString(),
    frontendUrl: process.env.FRONTEND_URL || 'Not specified'
  });
});

// 2. Chatbot & Storyteller AI Endpoint (Supporting client-provided or server-env keys)
const SYSTEM_PROMPT = `You are "Ayaz", the single, unique, official AI Tour Guide & Master Storyteller for the 'Karakalpak Travel' portal.
Speak like a wise, magnetic Karakalpak storyteller around a warm yurt campfire. Provide vivid historical facts, practical travel advice, and culture stories. Support any language requested by the user.`;

app.post('/api/chat', async (req, res) => {
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

// 3. Gemini Proxy Endpoint (Hides keys completely from client DevTools)
app.post('/api/gemini', async (req, res) => {
  try {
    const { contents, systemInstruction, model, generationConfig } = req.body;
    
    // Pool of server keys
    const serverKeys = [
      process.env.GEMINI_API_KEY_1,
      process.env.GEMINI_API_KEY_2,
      process.env.GEMINI_API_KEY_3,
      process.env.GEMINI_API_KEY_4
    ].filter(Boolean);

    // Client provided key (if set in UI settings) or server keys
    const clientKey = req.headers['x-user-gemini-key'] || req.body.userKey;
    const keysToTry = clientKey ? [clientKey, ...serverKeys] : serverKeys;

    if (keysToTry.length === 0) {
      return res.status(400).json({ error: 'No Gemini API keys configured on backend or provided by client' });
    }

    const targetModel = model || 'gemini-1.5-flash';
    const payload = { contents };
    if (systemInstruction) payload.systemInstruction = systemInstruction;
    if (generationConfig) payload.generationConfig = generationConfig;

    let lastError = null;
    for (const key of keysToTry) {
      try {
        const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${targetModel}:generateContent?key=${key}`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': key
          },
          body: JSON.stringify(payload)
        });

        if (response.status === 429 || response.status === 403) {
          lastError = await response.text();
          continue; // Try next key in pool
        }

        if (!response.ok) {
          const errText = await response.text();
          return res.status(response.status).json({ error: errText });
        }

        const data = await response.json();
        return res.json(data);
      } catch (err) {
        lastError = err.message;
      }
    }

    return res.status(502).json({ error: `All Gemini keys exhausted: ${lastError}` });
  } catch (error) {
    return res.status(500).json({ error: error.message || 'Gemini proxy error' });
  }
});

// 4. Visitor & Analytics Tracking Proxy
app.post('/api/track', async (req, res) => {
  try {
    const { sessionToken, pagePath, pageTitle, serviceUsed } = req.body;
    const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || '0.0.0.0';

    const supabaseUrl = process.env.SUPABASE_URL || 'https://ythdfltgdvfjllgyutnz.supabase.co';
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseServiceKey) {
      // Return lightweight acknowledgment if service key isn't set on backend
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

if (process.env.NODE_ENV !== 'production' || !process.env.VERCEL) {
  app.listen(PORT, () => {
    console.log(`🚀 Karakalpakstan Tourism Backend Server listening on port ${PORT}`);
  });
}

export default app;
