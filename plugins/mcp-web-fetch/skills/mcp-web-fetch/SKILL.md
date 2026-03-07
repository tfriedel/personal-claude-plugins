---
name: mcp-web-fetch
description: "Fallback web fetcher for when Claude's built-in WebFetch tool fails with 403/blocked errors. Uses gemini-cli to fetch content from URLs that restrict Claude's WebFetch (e.g., Reddit, Wikipedia). Use this skill whenever WebFetch returns a 403 Forbidden error, an access denied response, or any indication that the site is blocking the request. Do NOT use this as the first choice -- always try the built-in WebFetch tool first."
allowed-tools: Bash(gemini:*)
---

# MCP Web Fetch (Fallback)

A fallback for fetching web content when Claude's built-in WebFetch tool is blocked (403 Forbidden).

## When to use this

Use this **only** after the built-in WebFetch tool has failed with:
- 403 Forbidden
- Access Denied
- Cloudflare block pages
- "Claude Code is unable to fetch ..."
- Any other indication the site is refusing the request


Always try WebFetch first. This is the backup.

## How to fetch

Use `gemini` CLI in headless mode. Pass the URL and a prompt describing what to extract:

```bash
gemini -p "<prompt about the URL content>: <url>"
```

For example:

```bash
gemini -p "Summarize the main content of this page: https://www.reddit.com/r/LocalLLaMA/comments/1rmplvs/example_post/"
```

The result is returned on stdout.

## Prompt construction

Construct the gemini prompt the same way you would construct the `prompt` parameter for WebFetch -- describe what information you want to extract from the page, and include the URL in the prompt text.

If no specific prompt or extraction goal is given (the user just wants to "fetch" or "read" a page), use this default:

```bash
gemini -p "Fetch this web page and return its content as markdown: <url>"
```

## Important notes

- The URL must be included directly in the prompt string passed to `gemini -p`
- Output may be lengthy; parse/summarize as needed for the user
- This tool is read-only -- it does not modify any files
- The CLI command is `gemini` (not `gemini-cli`). If it's not installed, inform the user they need to install it (`npm install -g @anthropic-ai/gemini-cli`)
