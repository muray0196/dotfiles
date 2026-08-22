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

Configure Hermes to use SearXNG for `web_search` and Crawl4AI for
`web_extract` after the stack is running:

```bash
./scripts/setup-hermes-search.sh
```

The Hermes plugin reads the Crawl4AI token from the private search-stack
`.env`; it does not duplicate the token in Hermes configuration.
