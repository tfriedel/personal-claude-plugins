---
name: mcp-web-fetch
description: "Fallback web fetcher for when Claude's built-in WebFetch tool fails with 403/blocked errors. Calls the Gemini API (gemini-3.1-flash-lite + url_context tool) to fetch content from URLs that restrict Claude's WebFetch (e.g., Reddit, Wikipedia). Use this skill whenever WebFetch returns a 403 Forbidden error, an access denied response, or any indication that the site is blocking the request. Do NOT use this as the first choice -- always try the built-in WebFetch tool first."
allowed-tools: Bash(curl:*), Bash(jq:*)
---

# MCP Web Fetch (Fallback)

A fallback for fetching web content when Claude's built-in WebFetch tool is blocked (403 Forbidden). Calls the Gemini API directly with `curl`, so Google fetches the URL server-side and the model summarizes it — bypassing whatever was blocking your IP.

## When to use this

Use this **only** after the built-in WebFetch tool has failed with:
- 403 Forbidden
- Access Denied
- Cloudflare block pages
- "Claude Code is unable to fetch ..."
- Any other indication the site is refusing the request

Always try WebFetch first. This is the backup.

## How to fetch

Call the Gemini REST API with the `url_context` tool, using model `gemini-3.1-flash-lite`. Pass the URL inside the prompt text:

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=$GEMINI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "contents":[{"parts":[{"text":"<PROMPT INCLUDING URL>"}]}],
    "tools":[{"url_context":{}}]
  }' | jq -r '.candidates[0].content.parts[].text'
```

Example:

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=$GEMINI_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "contents":[{"parts":[{"text":"Summarize the main content of this page: https://www.reddit.com/r/LocalLLaMA/"}]}],
    "tools":[{"url_context":{}}]
  }' | jq -r '.candidates[0].content.parts[].text'
```

The summarized/extracted content prints to stdout.

## Authentication

Requires `GEMINI_API_KEY` in the environment. Get a key at https://aistudio.google.com/apikey.

Persist it in fish (this user's shell):

```fish
set -Ux GEMINI_API_KEY "your-key-here"
```

This skill deliberately uses the REST API instead of the `gemini` CLI so it does NOT depend on the CLI's auth config (which may be set to OAuth for normal use). The API key is used only for this skill; the rest of `gemini` keeps working with OAuth.

If `$GEMINI_API_KEY` is unset, the API will return an auth error — tell the user to export it and retry.

## Prompt construction

Construct the prompt the same way you would the `prompt` parameter for WebFetch — describe what to extract from the page, and include the URL in the prompt text. The `url_context` tool will follow the URL.

If no specific extraction goal was given (the user just wants to "fetch" or "read" the page), default to:

```
Fetch this web page and return its main content as markdown: <url>
```

## Error handling

Inspect the JSON response with `jq '.error'` if `.candidates[0].content.parts[].text` is empty. Common cases:
- `403`/auth error → `GEMINI_API_KEY` missing or invalid
- `429` `RESOURCE_EXHAUSTED` → quota exhausted, wait or use a different key
- Empty text + no error → the URL itself may have blocked Google's fetcher; report this to the user, do not silently return nothing

## Important notes

- The URL must appear in the prompt text (the `url_context` tool scans for URLs in the prompt)
- Output may be long; parse/summarize as needed for the user
- This tool is read-only — it does not modify any files
- Requires `curl` and `jq` (both standard on this machine)
