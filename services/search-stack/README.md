# Local search stack

Local search and page retrieval with SearXNG and Crawl4AI.

From the dotfiles repository, provision the stack with:

```bash
./scripts/setup-search-stack.sh
cd ~/services/search-stack
python3 scripts/search-and-crawl.py 'search query'
```

- SearXNG: http://localhost:8888
- Crawl4AI: http://localhost:11235/playground

The setup script generates and preserves the SearXNG secret, Crawl4AI API token,
and Crawl4AI signing key in `~/services/search-stack/.env`. The Python helper
reads the token from that file automatically. Set `SEARXNG_HOST_PORT` when
running the setup script to use a different local SearXNG port.

Configure Hermes after the stack is running:

```bash
./scripts/setup-hermes-search.sh
```

The Hermes plugin reads the Crawl4AI token from the private search-stack
`.env`; it does not duplicate the token in Hermes configuration. The setup
selects a three-result SearXNG fast lane, routes every model-facing search
result through Crawl4AI, sets legacy `web_extract` to a 4,000-character page
window (before its truncation footer), and disables external keyless rescue
after a local backend failure.

Hermes receives two staged retrieval paths:

- `web_search`: normal mode. Discovers up to three URLs through the
  `google` SearXNG profile, opens results concurrently through Crawl4AI, and
  replaces every returned snippet with a query-relevant page passage. If the
  primary search fails, has no relevant candidates, or produces no crawlable
  context, one DuckDuckGo Web retry runs through SearXNG before failing
  closed. Weather and news candidates must preserve the matching query intent,
  rather than passing on location words alone. Raw snippets never reach the
  model. Each accepted result is replaced with Crawl4AI's page Markdown
  directly, without query-passage selection or a plugin-level search-context
  cap.
- `web_open`: targeted mode. Opens one URL by default (at most two), selects
  relevant passages, returns at most 4,000 content characters per source, and
  caps the serialized JSON payload at 12,000 characters.

For deep or multi-source requests, the agent runs up to three focused
`web_search` calls. Every result still follows the same required Crawl4AI path;
there is no separate research mode.

Normal extraction uses Crawl4AI's compact `/md` response with cache reads
disabled (`c=0`); Hermes retains its correctly keyed local cache. Explicit
HTML extraction keeps `/crawl` only as a compatibility path. Plugin prompt
policy applies to new Hermes sessions after the plugin is reloaded.

All page retrieval composes Hermes' core web tools so URL-secret, SSRF,
site-policy, and extraction-cache checks remain active. Nested `web_open`
dispatch does not consume model-loop search counters; the plugin enforces its
own two-URL limit.
The plugin also clamps direct model-issued `web_extract` requests to the
configured 4,000-character ceiling and removes truncation/spillover pointers.
Its execution middleware blocks direct model-issued extraction entirely and
routes the agent toward Crawl4AI-optimized search results or deferred
`web_open`. Its larger internal window remains available because staged nested
dispatch bypasses the model-facing guard and is compacted before reaching the
model.
