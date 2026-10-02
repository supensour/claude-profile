# claude-glm

Isolated Claude Code setup for the [Z.ai GLM API](https://docs.z.ai/devpack/tool/claude) — keeps your personal GLM usage completely separate from any other Claude Code login (e.g. a company Team account in `~/.claude`).

## Why

Running Claude Code with `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` pointed at GLM routes **model traffic** (prompts, code, outputs) to Z.ai — but if company credentials still exist in `~/.claude`, Claude Code keeps fetching **Enterprise managed settings (remote)** from the company org, which can inject things like OTel exporter endpoints into your "personal" sessions.

This script removes that path entirely: a separate `CLAUDE_CONFIG_DIR` means no company credentials, no remote managed settings, no org identity — plus defensive scrubbing of OTel/telemetry env vars at launch.

## What it creates

| Path | Purpose |
|---|---|
| `~/.claude-personal/settings.json` | GLM endpoint, your API key (mode `600`), telemetry off, nonessential Anthropic traffic off |
| shell function in `~/.zshrc` | launcher that scrubs `OTEL_*` / `CLAUDE_CODE_ENABLE_TELEMETRY` and sets `CLAUDE_CONFIG_DIR` before calling `claude` |

Sessions, plugins, credentials, and transcripts all live under the config dir — one folder to inspect or wipe.

## Usage

```sh
./setup.sh             # interactive — prompts for everything below
./setup.sh --remove    # removes the launcher; optionally deletes the config dir
```

Prompts (all have defaults except the key):

1. **Launcher name** — the shell command, e.g. `claude-personal`
2. **Config directory** — e.g. `~/.claude-personal` (must be under `$HOME`, refuses `~/.claude`)
3. **Base URL** — default `https://api.z.ai/api/anthropic`; use `https://open.bigmodel.cn/api/anthropic` if your key is from bigmodel.cn
4. **API key** — hidden input; stored only in `settings.json`, never echoed, never committed

## Verify after first launch

Run `/status` inside the session and check:

```
Auth token:          ANTHROPIC_AUTH_TOKEN
Anthropic base URL:  https://api.z.ai/api/anthropic
Setting sources:     User settings only        ← no "Enterprise managed settings (remote)"
Organization:        (absent)
```

If "Enterprise managed settings (remote)" still appears, run `/logout` once inside the personal launcher (macOS Keychain may share credentials between config dirs), then re-login in your normal `claude` if needed.

## Ground rules

- `claude-personal` **only in personal repos** — company code on a personal API account is a compliance risk in the opposite direction.
- Plugins install separately per config dir: `claude-personal plugin marketplace add github:owner/repo`.
- Company setup (`claude`, `~/.claude`) is never touched by this script.
