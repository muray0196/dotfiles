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
selects a three-result SearXNG fast lane, sets legacy `web_extract` to a
4,000-character page window (before its truncation footer), and disables
external keyless rescue after a local backend failure.

Hermes receives three staged retrieval paths:

- `web_search`: normal mode. Returns up to three compact snippets through the
  three-result `google cse` SearXNG profile, applies a 6,000-character
  result-field budget, and does not crawl pages.
- `web_open`: targeted mode. Opens one URL by default (at most two), selects
  relevant passages, returns at most 4,000 content characters per source, and
  caps the serialized JSON payload at 12,000 characters.
- `web_research`: explicit deep mode. Searches one to three queries, removes
  duplicate URLs, diversifies domains, fetches up to five pages with bounded
  concurrency, and enforces a 14,000-character content budget plus an
  18,000-character serialized JSON ceiling.

Normal extraction uses Crawl4AI's compact `/md` response with cache reads
disabled (`c=0`); Hermes retains its correctly keyed local cache. Explicit
HTML extraction keeps `/crawl` only as a compatibility path. Plugin prompt
policy applies to new Hermes sessions after the plugin is reloaded.

`web_open` and `web_research` compose Hermes' core web tools so URL-secret,
SSRF, site-policy, and extraction-cache checks remain active. Their nested
dispatch does not consume model-loop search counters; the plugin instead
enforces fixed handler limits of two URLs, three queries, and five sources.
