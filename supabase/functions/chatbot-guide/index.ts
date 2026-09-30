import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const SYSTEM_PROMPT = `You are "Ayaz", the single, unique, official AI Tour Guide & Master Storyteller for the 'Karakalpak Travel' portal.

Voice & Persona:
You possess 1 single, iconic, and unforgettable voice persona: warm, cozy, deeply magnetic, charismatic, and eloquent. You speak like a wise and welcoming Karakalpak storyteller (jirau/bakhshi) sitting with a traveler around a warm campfire in a traditional yurt. Your words draw the traveler in, evoking the magic of the endless steppes, the Aral Sea, ancient fortresses, and generous Karakalpak hospitality.

Core Capabilities:
1. Global Multilingual Support: Automatically detect and communicate in ANY world language (English, Russian, Uzbek, Kazakh, Karakalpak, French, German, etc.). Reply in the exact language the traveler speaks.
2. Virtual On-Site Guide Function: Provide rich, vivid historical facts, emotional storytelling, legends, and captivating details about locations (Muynak, Aral Sea, Savitsky Museum, Mizdakhan, Ayaz-Kala, etc.).
3. Budget & Practical Advice: Help travelers with affordable options, yurt stays, transport, local cuisine (beshbarmak, jueri gurtik, fried Aral pike-perch), and essential travel tips.
4. Tone: Extremely welcoming, cozy, respectful, inspiring, and eloquent. Structure replies neatly with bullet points.`;

interface Message {
  role: "user" | "assistant" | "system";
  content: string;
}

// In-memory sliding window rate limiter: max 20 requests per minute per IP
const rateLimitMap = new Map<string, { count: number; resetTime: number }>();

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now > entry.resetTime) {
    rateLimitMap.set(ip, { count: 1, resetTime: now + 60_000 });
    return false;
  }
  if (entry.count >= 20) {
    return true;
  }
  entry.count++;
  return false;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const clientIp = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "anonymous";
  if (isRateLimited(clientIp)) {
    return new Response(
      JSON.stringify({ error: "Rate limit exceeded. Please wait 60 seconds before sending more requests." }),
      {
        status: 429,
        headers: { ...corsHeaders, "Content-Type": "application/json", "Retry-After": "60" },
      }
    );
  }

  try {
    const body = (await req.json()) as {
      messages?: Message[];
      action?: "chat" | "tts";
      text?: string;
    };

    const apiKey = Deno.env.get("OPENAI_API_KEY");

    if (!apiKey) {
      return new Response(
        JSON.stringify({
          error: "OPENAI_API_KEY secret is not configured. Add it in Supabase Edge Functions > Secrets.",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // --- Text-to-Speech action ---
    if (body.action === "tts") {
      const text = body.text?.trim();
      if (!text) {
        return new Response(JSON.stringify({ error: "text is required for tts" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const ttsRes = await fetch("https://api.openai.com/v1/audio/speech", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: "tts-1",
          voice: "nova",
          input: text.slice(0, 500),
          response_format: "mp3",
        }),
      });

      if (!ttsRes.ok) {
        const errText = await ttsRes.text();
        return new Response(
          JSON.stringify({ error: `TTS API error: ${ttsRes.status} — ${errText}` }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const audioBuffer = await ttsRes.arrayBuffer();
      return new Response(audioBuffer, {
        headers: {
          ...corsHeaders,
          "Content-Type": "audio/mpeg",
          "Content-Disposition": "inline; filename=guide.mp3",
        },
      });
    }

    // --- Chat action (default) ---
    const { messages } = body;

    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: "messages array is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Sanitize and cap conversation depth (max 8 messages, max 1000 chars each) to prevent token abuse
    const sanitizedMessages: Message[] = messages.slice(-8).map((m) => ({
      role: m.role === "assistant" ? "assistant" : "user",
      content: String(m.content || "").slice(0, 1000),
    }));

    const chatMessages: Message[] = [{ role: "system", content: SYSTEM_PROMPT }, ...sanitizedMessages];

    const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: chatMessages,
        max_tokens: 450,
        temperature: 0.7,
      }),
    });

    if (!openaiRes.ok) {
      const errText = await openaiRes.text();
      return new Response(
        JSON.stringify({ error: `OpenAI API error: ${openaiRes.status} — ${errText}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const data = await openaiRes.json();
    const reply = data.choices?.[0]?.message?.content ?? "Sorry, I could not generate a response.";

    return new Response(JSON.stringify({ reply }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Unknown error";
    return new Response(JSON.stringify({ error: `Request failed: ${msg}` }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
