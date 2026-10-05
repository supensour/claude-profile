# claude-profile

Profile manager for running [Claude Code](https://code.claude.com/docs/) on an alternate Anthropic-compatible API. Each profile is an isolated Claude Code config dir, so that usage stays completely separate from any other Claude Code login (e.g. a company Team account in `~/.claude`) — no shell alias needed.

Currently only the [Z.ai GLM API](https://docs.z.ai/devpack/tool/claude) is supported.

## Why

Running Claude Code with `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` pointed at GLM routes **model traffic** (prompts, code, outputs) to Z.ai — but if company credentials exist in `~/.claude`, Claude Code keeps fetching **Enterprise managed settings (remote)** from the org, which can inject OTel exporter endpoints into your "personal" sessions.

Each profile removes that path entirely: a separate `CLAUDE_CONFIG_DIR` means no company credentials, no remote managed settings, no org identity — plus `run` defensively scrubs OTel/telemetry env vars before launching.

## Install

Clone the repo, then symlink it onto PATH:

```sh
git clone https://github.com/supensour/claude-profile.git
cd claude-profile
./claude-profile install     # symlinks `claude-profile` onto PATH (~/.local/bin)
```

Or, without cloning — download the script straight onto PATH:

```sh
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/supensour/claude-profile/master/claude-profile -o ~/.local/bin/claude-profile
chmod +x ~/.local/bin/claude-profile
```

(add `~/.local/bin` to `PATH` if it isn't already — `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh`)

## Usage

```sh
claude-profile profiles list                # list profiles (* marks the default)
claude-profile profiles add personal        # create/overwrite a profile (interactive)
claude-profile profiles remove personal     # delete a profile (asks about its dir)

claude-profile profiles default             # show the current default profile
claude-profile profiles default personal    # set the default profile
claude-profile profiles default --unset     # delete the default profile

claude-profile run personal                 # launch Claude Code on that profile
claude-profile run                          # default profile (or the only one)
claude-profile run personal -- --version    # everything after -- goes to the claude CLI
claude-profile run work -- -p "summarize"   # one-shot prompt on the "work" profile

claude-profile install                      # put claude-profile on PATH
claude-profile uninstall                    # remove it from PATH
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

## Layout

| Path                                | Purpose                                                 |
| ----------------------------------- | ------------------------------------------------------- |
| `~/.claude-profile/profiles.json`   | registry: profile name → config dir, endpoint, key hint |
| `~/.claude-<profile>/settings.json` | GLM endpoint + API key (mode `600`), telemetry off      |

The API key lives **only** in the profile's `settings.json` — never in the registry, never echoed, never committed.

## Platform support

- **macOS / Linux** — works out of the box (bash + python3)
- **Windows** — run under **Git Bash or WSL** (not native cmd/PowerShell): `install` copies the script instead of symlinking (MSYS symlinks need admin rights), and python is detected as `python3` / `python` / `py -3`
- `.gitattributes` keeps the script LF-only so Windows checkouts don't break bash
- Output is colorized on interactive terminals; set `NO_COLOR=1` (or `TERM=dumb`) to disable

## Ground rules

- `claude-profile run` **only in personal repos**
- Plugins install per profile: `claude-profile run personal -- plugin marketplace add github:owner/repo`.
- Your company setup (`claude`, `~/.claude`) is never touched.
- Sessions/transcripts for each profile live under its config dir — delete the profile to wipe everything.
