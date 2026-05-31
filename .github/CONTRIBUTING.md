# Contributing

PRs and issues are welcome.

## Development setup

```bash
git clone https://github.com/yourusername/ai-agent-bridge
cd ai-agent-bridge
```

## Testing

```bash
bash tests/test-peer-bridge.sh
```

## Code style

- Shell scripts: `bash -n` must pass, `shellcheck` warnings should be addressed
- Use `set -euo pipefail` in all scripts
- Keep scripts self-contained (no external runtime dependencies beyond `curl` and `jq`)

## Submitting a PR

1. Fork the repo
2. Create a branch: `git checkout -b feature/your-feature`
3. Commit with a short descriptive message
4. Open a PR against `main`
