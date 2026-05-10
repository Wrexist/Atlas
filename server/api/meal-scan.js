/**
 * Vercel serverless proxy for the PeptideX meal scanner.
 *
 * Why this exists: the iOS client at MealScannerService.swift can hit
 * Anthropic's Messages API directly using an API key embedded in the
 * shipping binary, which is unsafe — anyone who jailbreaks an iPhone
 * can extract the key. This function holds the key server-side and
 * forwards the request body unchanged, so the client never sees it.
 *
 * Deploy:
 *   1. Push this directory to a GitHub repo (or `vercel deploy` it).
 *   2. In the Vercel dashboard, set the env var ANTHROPIC_API_KEY to
 *      your Anthropic key.
 *   3. Add MEAL_SCANNER_ENDPOINT = https://<your-deploy>.vercel.app/api/meal-scan
 *      to the iOS app's Info.plist (or scheme env var). The client
 *      already supports the override — see MealScannerService.swift.
 *
 * Body shape: identical to api.anthropic.com/v1/messages — model,
 * max_tokens, messages — so the proxy is a 1:1 forward. The client
 * doesn't need to know it's talking to a proxy.
 */
export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Use POST' } });
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    res.status(500).json({
      error: { message: 'ANTHROPIC_API_KEY not configured on the proxy' }
    });
    return;
  }

  // Defensive size cap — the iOS client compresses to 1024 px max edge
  // at JPEG quality 0.7, which is well under 5 MB even for 12-megapixel
  // originals. Reject anything significantly larger to avoid abuse.
  const contentLength = parseInt(req.headers['content-length'] || '0', 10);
  if (contentLength > 7 * 1024 * 1024) {
    res.status(413).json({
      error: { message: 'Request too large; resize the photo before retrying' }
    });
    return;
  }

  try {
    const upstream = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      // req.body is parsed by Vercel for application/json — re-stringify
      // so the upstream sees an identical byte sequence to what a direct
      // client call would have sent.
      body: typeof req.body === 'string' ? req.body : JSON.stringify(req.body),
    });

    const text = await upstream.text();
    res.status(upstream.status);
    // Forward upstream content-type so JSON parsing on the client side
    // works without sniffing.
    const upstreamContentType = upstream.headers.get('content-type') || 'application/json';
    res.setHeader('Content-Type', upstreamContentType);
    res.send(text);
  } catch (err) {
    res.status(502).json({
      error: { message: `Proxy upstream failure: ${err.message || String(err)}` }
    });
  }
}

export const config = {
  // 1024 px / quality 0.7 JPEGs land around 200-400 KB; allow up to 7 MB
  // to leave headroom for the JSON envelope and base64 expansion.
  api: {
    bodyParser: {
      sizeLimit: '7mb',
    },
  },
};
