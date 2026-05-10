# PeptideX meal-scan proxy

A one-file Vercel serverless function that holds the Anthropic API key
on the server side so the iOS app's `MealScannerService` doesn't have
to embed it in the shipping binary.

## Why

`MealScannerService.swift` reads `Info.plist[ANTHROPIC_API_KEY]` (or
the `ANTHROPIC_API_KEY` process-env var) and calls
`api.anthropic.com/v1/messages` directly. That works for development,
but anyone who jailbreaks an installed iPhone can extract the key.
The proxy fixes that without touching the iOS code — the client
already supports an `MEAL_SCANNER_ENDPOINT` override.

## Deploy

1. Install the Vercel CLI if you don't have it: `npm i -g vercel`.
2. From this directory: `vercel deploy --prod`.
3. In the Vercel dashboard for the new project, set the environment
   variable `ANTHROPIC_API_KEY` to your real key. Mark it as
   "Production / Preview / Development" so all deploys see it.
4. Note the deploy URL (e.g. `https://peptidex-proxy.vercel.app`).

## Wire the iOS app

Add to `Peptide/Resources/Info.plist`:

```xml
<key>MEAL_SCANNER_ENDPOINT</key>
<string>https://peptidex-proxy.vercel.app/api/meal-scan</string>
```

Or set it via a gitignored `Secrets.xcconfig` and reference
`$(MEAL_SCANNER_ENDPOINT)` from Info.plist so different builds can
point at different proxies.

The iOS code resolves this at call time — the next build will route
through the proxy with no further changes.

## Body shape

The proxy is a 1:1 forward to `api.anthropic.com/v1/messages`. The
client sends the standard Messages API JSON body:

```json
{
  "model": "claude-sonnet-4-6",
  "max_tokens": 400,
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": "..." } },
        { "type": "text", "text": "Identify the meal..." }
      ]
    }
  ]
}
```

The proxy adds `x-api-key` and `anthropic-version` headers and forwards
the rest unchanged.

## Limits

- Body size cap: 7 MB (the iOS client compresses to ~200-400 KB at
  1024 px / quality 0.7, well under).
- Method: POST only.
- No rate limiting — add Vercel Edge Middleware if you need it.
