# claude-glm

Profile manager for running [Claude Code](https://code.claude.com/docs/) on the [Z.ai GLM API](https://docs.z.ai/devpack/tool/claude). Each profile is an isolated Claude Code config dir, so your GLM usage stays completely separate from any other Claude Code login (e.g. a company Team account in `~/.claude`) — no shell alias needed.

## Platform support

- **macOS / Linux** — works out of the box (bash + python3)
- **Windows** — run under **Git Bash or WSL** (not native cmd/PowerShell): `install` copies the script instead of symlinking (MSYS symlinks need admin rights), and python is detected as `python3` / `python` / `py -3`
- `.gitattributes` keeps the script LF-only so Windows checkouts don't break bash
- Output is colorized on interactive terminals; set `NO_COLOR=1` (or `TERM=dumb`) to disable

## Why

Running Claude Code with `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` pointed at GLM routes **model traffic** (prompts, code, outputs) to Z.ai — but if company credentials exist in `~/.claude`, Claude Code keeps fetching **Enterprise managed settings (remote)** from the org, which can inject OTel exporter endpoints into your "personal" sessions.

Each profile removes that path entirely: a separate `CLAUDE_CONFIG_DIR` means no company credentials, no remote managed settings, no org identity — plus `run` defensively scrubs OTel/telemetry env vars before launching.

## Layout

| Path | Purpose |
|---|---|
| `~/.claude-glm/profiles.json` | registry: profile name → config dir, endpoint, key hint |
| `~/.claude-<profile>/settings.json` | GLM endpoint + API key (mode `600`), telemetry off |

The API key lives **only** in the profile's `settings.json` — never in the registry, never echoed, never committed.

## Install

```sh
./claude-glm install     # symlinks `claude-glm` onto PATH (~/.local/bin)
```

## Usage

```sh
claude-glm profiles add personal        # create/overwrite a profile (interactive)
claude-glm profiles list                # list profiles (* marks the default)
claude-glm profiles remove personal     # drop a profile (asks about its dir)

claude-glm profiles default personal    # set the default profile
claude-glm profiles default             # show the current default
claude-glm profiles default --unset     # clear it

claude-glm run personal                 # launch Claude Code on that profile
claude-glm run personal -- --version    # extra args pass through to claude
claude-glm run                          # default profile (or the only one)

claude-glm install / uninstall          # manage the PATH symlink
```

When `run` is called without a profile name, resolution order is:
explicit default (`profiles default`) → the only existing profile → error with a hint.

`profiles add` prompts for:

1. **Profile name** (or pass it as the argument)
2. **Config directory** — default `~/.claude-<name>` (must be under `$HOME`, refuses `~/.claude`)
3. **Base URL** — default `https://api.z.ai/api/anthropic`; use `https://open.bigmodel.cn/api/anthropic` if your key is from bigmodel.cn
4. **API key** — hidden input

## Verify after first launch

Run `/status` inside the session and check:

```
Auth token:          ANTHROPIC_AUTH_TOKEN
Anthropic base URL:  https://api.z.ai/api/anthropic
Setting sources:     User settings only        ← no "Enterprise managed settings (remote)"
Organization:        (absent)
```

If "Enterprise managed settings (remote)" still appears, run `/logout` once inside the profile session (macOS Keychain may share credentials between config dirs), then re-login in your normal `claude` if needed.

## Ground rules

- `claude-glm run` **only in personal repos** — company code on a personal API account is a compliance risk in the opposite direction.
- Plugins install per profile: `claude-glm run personal -- plugin marketplace add github:owner/repo`.
- Your company setup (`claude`, `~/.claude`) is never touched.
- Sessions/transcripts for each profile live under its config dir — delete the profile to wipe everything.

## Migrating from the old setup.sh

The previous `setup.sh` installed a shell function in `~/.zshrc` between `# >>> claude-glm` and `# <<< claude-glm <<<` markers. Delete that block (or run `grep -n 'claude-glm' ~/.zshrc` to find it); profiles replace it.
