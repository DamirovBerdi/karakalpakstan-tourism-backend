const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

const visitorRateLimitMap = new Map<string, { count: number; resetTime: number }>();

function isTrackRateLimited(ip: string): boolean {
  const now = Date.now();
  const entry = visitorRateLimitMap.get(ip);
  if (!entry || now > entry.resetTime) {
    visitorRateLimitMap.set(ip, { count: 1, resetTime: now + 60000 });
    return false;
  }
  if (entry.count >= 60) {
    return true;
  }
  entry.count++;
  return false;
}

function getClientIP(req: Request): string {
  const headers = req.headers;
  const cfConnecting = headers.get('cf-connecting-ip');
  if (cfConnecting) return cfConnecting.trim();
  const realIp = headers.get('x-real-ip');
  if (realIp) return realIp.trim();
  const forwarded = headers.get('x-forwarded-for');
  if (forwarded) {
    const ips = forwarded.split(',').map((ip: string) => ip.trim()).filter(Boolean);
    if (ips.length > 0) return ips[ips.length - 1];
  }
  const trueClient = headers.get('true-client-ip');
  if (trueClient) return trueClient.trim();
  return '0.0.0.0';
}

function extractCountry(req: Request): string {
  const cfCountry = req.headers.get('cf-ipcountry');
  if (cfCountry) return cfCountry;
  const xCountry = req.headers.get('x-vercel-ip-country');
  if (xCountry) return xCountry;
  return '';
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  const ip = getClientIP(req);
  if (isTrackRateLimited(ip)) {
    return new Response(JSON.stringify({ error: 'Rate limit exceeded' }), {
      status: 429,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = await req.json();
    const { sessionToken, pagePath, pageTitle, serviceUsed } = body;
    if (!sessionToken) {
      return new Response(JSON.stringify({ error: 'sessionToken required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const country = extractCountry(req);
    const userAgent = req.headers.get('user-agent') ?? '';

    // Save directly using Supabase REST API via native fetch! Zero external dependencies!
    const restHeaders = {
      'apikey': supabaseServiceKey,
      'Authorization': 'Bearer ' + supabaseServiceKey,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates'
    };

    // 1. Upsert session
    await fetch(supabaseUrl + '/rest/v1/visitor_sessions', {
      method: 'POST',
      headers: restHeaders,
      body: JSON.stringify({
        session_token: sessionToken,
        ip_address: ip,
        country: country || undefined,
        user_agent: userAgent,
        last_seen: new Date().toISOString()
      })
    });

    // 2. Insert page view
    await fetch(supabaseUrl + '/rest/v1/page_views', {
      method: 'POST',
      headers: { ...restHeaders, 'Prefer': 'return=minimal' },
      body: JSON.stringify({
        session_token: sessionToken,
        page_path: pagePath ?? '/',
        page_title: pageTitle ?? '',
        service_used: serviceUsed ?? ''
      })
    });

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err?.message ?? 'Internal error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});