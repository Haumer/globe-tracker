// Cloudflare Worker — OpenSky API Proxy
// Bypasses OpenSky's cloud-provider IP blocking (AWS/Heroku)
// Deploy: npx wrangler deploy
//
// Usage: replace opensky-network.org with your worker URL
//   GET  https://<worker>.workers.dev/api/states/all?lamin=47&lamax=48&...
//   GET  https://<worker>.workers.dev/api/routes?callsign=AUA123
//   POST https://<worker>.workers.dev/auth/token  (form: grant_type, client_id, client_secret)

const OPENSKY_API = "https://opensky-network.org"
const OPENSKY_AUTH = "https://auth.opensky-network.org"

// Simple in-memory token cache (persists across requests within the same isolate)
let cachedToken = null
let tokenExpiresAt = 0

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    const path = url.pathname

    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() })
    }

    // Validate API key if configured
    if (env.PROXY_API_KEY) {
      const authHeader = request.headers.get("X-Proxy-Key")
      if (authHeader !== env.PROXY_API_KEY) {
        return jsonResponse({ error: "Unauthorized" }, 401)
      }
    }

    try {
      // Token endpoint
      if (path === "/auth/token" && request.method === "POST") {
        return await handleTokenRequest(request)
      }

      // API proxy — forward to opensky-network.org
      if (path.startsWith("/api/")) {
        return await handleApiRequest(request, url, env)
      }

      // Debug/health endpoint
      if (path === "/health") {
        const info = { status: "ok", hasCredentials: !!(env.OPENSKY_ID && env.OPENSKY_SECRET) }
        try {
          const authResp = await fetch(
            `${OPENSKY_AUTH}/auth/realms/opensky-network/protocol/openid-connect/token`,
            {
              method: "POST",
              headers: { "Content-Type": "application/x-www-form-urlencoded" },
              body: `grant_type=client_credentials&client_id=${encodeURIComponent(env.OPENSKY_ID)}&client_secret=${encodeURIComponent(env.OPENSKY_SECRET)}`,
            }
          )
          info.authStatus = authResp.status
          info.authBody = await authResp.text().then(t => t.substring(0, 300))
        } catch (e) {
          info.tokenError = e.message
        }
        return jsonResponse(info)
      }

      return jsonResponse({ error: "Not found" }, 404)
    } catch (err) {
      return jsonResponse({ error: err.message }, 502)
    }
  }
}

async function handleTokenRequest(request) {
  const body = await request.text()
  const resp = await fetch(
    `${OPENSKY_AUTH}/auth/realms/opensky-network/protocol/openid-connect/token`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body,
    }
  )

  const data = await resp.json()

  // Cache token in isolate memory
  if (data.access_token) {
    cachedToken = data.access_token
    tokenExpiresAt = Date.now() + (data.expires_in || 1800) * 1000 - 60000
  }

  return jsonResponse(data, resp.status)
}

async function handleApiRequest(request, url, env) {
  // Build upstream URL
  const upstream = new URL(url.pathname + url.search, OPENSKY_API)

  // Get auth token — either from request header or cached
  let token = request.headers.get("Authorization")?.replace("Bearer ", "")

  if (!token && env.OPENSKY_ID && env.OPENSKY_SECRET) {
    token = await getToken(env.OPENSKY_ID, env.OPENSKY_SECRET)
  }

  const headers = {}
  if (token) headers["Authorization"] = `Bearer ${token}`

  const resp = await fetch(upstream.toString(), { headers })

  // Stream response back with CORS headers
  return new Response(resp.body, {
    status: resp.status,
    headers: {
      ...corsHeaders(),
      "Content-Type": resp.headers.get("Content-Type") || "application/json",
      "Cache-Control": "public, max-age=10",
    },
  })
}

async function getToken(clientId, clientSecret) {
  if (cachedToken && Date.now() < tokenExpiresAt) return cachedToken

  const resp = await fetch(
    `${OPENSKY_AUTH}/auth/realms/opensky-network/protocol/openid-connect/token`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `grant_type=client_credentials&client_id=${encodeURIComponent(clientId)}&client_secret=${encodeURIComponent(clientSecret)}`,
    }
  )

  if (!resp.ok) return null

  const data = await resp.json()
  cachedToken = data.access_token
  tokenExpiresAt = Date.now() + (data.expires_in || 1800) * 1000 - 60000
  return cachedToken
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Proxy-Key",
  }
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  })
}
