#!/usr/bin/env bash
#
# claude-glm — isolated Claude Code setup for the Z.ai GLM API.
#
# Creates a separate Claude Code config directory (GLM endpoint + your API key)
# and installs a shell launcher function that:
#   - points Claude Code at the GLM Anthropic-compatible endpoint
#   - scrubs OTEL_* / telemetry env vars before launching
#   - keeps credentials, plugins, and sessions fully separate from any other
#     Claude Code login (e.g. a company account in ~/.claude)
#
# Usage:
#   ./setup.sh            interactive setup (prompts for alias, dir, key)
#   ./setup.sh --remove   uninstall the launcher (optionally delete the config dir)
#   ./setup.sh -h | --help
#
set -euo pipefail

RC_BEGIN="# >>> claude-glm (managed by claude-glm/setup.sh) >>>"
RC_END="# <<< claude-glm <<<"

DEFAULT_ALIAS="claude-personal"
DEFAULT_DIR="$HOME/.claude-personal"
DEFAULT_BASE_URL="https://api.z.ai/api/anthropic"

# --- output ------------------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info() { printf '%s\n' "${GREEN}✔${RESET} $*"; }
warn() { printf '%s\n' "${YELLOW}⚠${RESET} $*" >&2; }
die()  { printf '%s\n' "${RED}✖ $*${RESET}" >&2; exit 1; }

header() {
  printf '%s\n' "${BOLD}claude-glm — isolated Claude Code launcher for GLM${RESET}"
  printf '%s\n' "${DIM}Keeps your GLM setup separate from any other Claude Code login.${RESET}"
  echo
}

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

# --- helpers ------------------------------------------------------------------
json_escape() {
  # double backslashes first, then escape quotes (order matters)
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

sed_escape() {
  # escapes a replacement string for sed's s|...|...| form; reads stdin
  sed -e 's/[\\&|]/\\&/g'
}

resolve_dir() {
  local d=$1
  case $d in
    "~/"*) d="$HOME/${d#\~/}" ;;
    /*)    : ;;
    *)     d="$HOME/$d" ;;
  esac
  printf '%s' "$d"
}

pick_rc_file() {
  local shell_name rc
  shell_name=$(basename "${SHELL:-/bin/zsh}")
  case $shell_name in
    zsh) rc="$HOME/.zshrc" ;;
    *)   rc="$HOME/.bashrc" ;;
  esac
  printf '%s' "$rc"
}

# Reads a line from the controlling terminal (falls back to stdin).
ask() { # ask "Question" "default" -> sets REPLY
  local question=$1 default=$2
  if [ -e /dev/tty ]; then
    printf '%s' "${BOLD}${question}${RESET} ${DIM}[${default}]${RESET}: "
    read -r REPLY </dev/tty || die "aborted"
  else
    printf '%s' "${BOLD}${question}${RESET} ${DIM}[${default}]${RESET}: "
    read -r REPLY || die "aborted (no tty and no stdin)"
  fi
  REPLY=${REPLY:-$default}
}

ask_secret() { # ask_secret "Question" -> sets REPLY
  printf '%s' "${BOLD}$1${RESET} ${DIM}(input hidden)${RESET}: "
  read -rs REPLY </dev/tty 2>/dev/null || read -rs REPLY || die "aborted"
  echo >&2
}

remove_rc_block() { # remove_rc_block <rcfile>
  local rc=$1
  [ -f "$rc" ] || return 0
  awk -v begin="$RC_BEGIN" -v end="$RC_END" '
    $0 == begin { inblock = 1 }
    !inblock    { print }
    $0 == end   { inblock = 0 }
  ' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
}

# --- init ----------------------------------------------------------------------
cmd_init() {
  header

  command -v claude >/dev/null 2>&1 \
    || warn "claude not found on PATH — setup will continue, install Claude Code first to use it."

  # 1) launcher name
  while :; do
    ask "Launcher name (shell command)" "$DEFAULT_ALIAS"
    case $REPLY in
      *[!a-zA-Z0-9_-]*|[0-9-]*) warn "Use letters, digits, _ or - (must not start with a digit or -)." ;;
      ?*) break ;;
      *) warn "Name cannot be empty." ;;
    esac
  done
  ALIAS_NAME=$REPLY

  # 2) config directory
  while :; do
    ask "Config directory" "$DEFAULT_DIR"
    CONFIG_DIR=$(resolve_dir "$REPLY")
    case $CONFIG_DIR in
      "$HOME"|"$HOME/.claude"|/) die "Refusing to use '$CONFIG_DIR' as the config dir — that would collide with your existing setup." ;;
    esac
    case $CONFIG_DIR in
      "$HOME"/*) break ;;
      *) warn "Please choose a directory under \$HOME." ;;
    esac
  done

  # 3) base URL (z.ai default; bigmodel.cn users override)
  ask "GLM Anthropic-compatible base URL" "$DEFAULT_BASE_URL"
  BASE_URL=$REPLY

  # 4) API key (hidden input)
  while :; do
    ask_secret "GLM API key"
    API_KEY=$REPLY
    [ "${#API_KEY}" -ge 8 ] && break
    warn "That key looks too short — try again (Ctrl-C to abort)."
  done

  echo

  # confirm overwrite
  if [ -f "$CONFIG_DIR/settings.json" ]; then
    ask "settings.json already exists in $CONFIG_DIR — overwrite?" "yes"
    case $REPLY in y|Y|yes|YES) ;; *) die "aborted (nothing was changed)";; esac
  fi

  # write settings.json (template + placeholder substitution; no eval, no echo of the key)
  mkdir -p "$CONFIG_DIR"
  umask 077
  SETTINGS_TEMPLATE='{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "__KEY__",
    "ANTHROPIC_BASE_URL": "__URL__",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.3[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5.3[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5.3-flash[1m]",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "OTEL_METRICS_EXPORTER": "none",
    "OTEL_LOGS_EXPORTER": "none"
  },
  "skipWebFetchPreflight": true
}'
  printf '%s\n' "$SETTINGS_TEMPLATE" \
    | sed -e "s|__KEY__|$(json_escape "$API_KEY" | sed_escape)|g" \
          -e "s|__URL__|$(json_escape "$BASE_URL" | sed_escape)|g" \
    > "$CONFIG_DIR/settings.json"
  chmod 600 "$CONFIG_DIR/settings.json"
  info "Wrote $CONFIG_DIR/settings.json (mode 600)"

  # write launcher into shell rc (replace previous managed block if present)
  RC_FILE=$(pick_rc_file)
  remove_rc_block "$RC_FILE"
  RC_DIR=${CONFIG_DIR/#"$HOME"/'$HOME'}
  LAUNCHER_TEMPLATE='__ALIAS__() {
  env -u OTEL_EXPORTER_OTLP_LOGS_ENDPOINT -u OTEL_EXPORTER_OTLP_METRICS_ENDPOINT -u OTEL_EXPORTER_OTLP_ENDPOINT -u OTEL_EXPORTER_OTLP_TRACES_ENDPOINT -u CLAUDE_CODE_ENABLE_TELEMETRY CLAUDE_CONFIG_DIR="__DIR__" claude "$@"
}'
  LAUNCHER=$(printf '%s\n' "$LAUNCHER_TEMPLATE" \
    | sed -e "s|__ALIAS__|$(printf '%s' "$ALIAS_NAME" | sed_escape)|g" -e "s|__DIR__|$(printf '%s' "$RC_DIR" | sed_escape)|g")
  {
    printf '\n%s\n' "$RC_BEGIN"
    printf '%s\n' "$LAUNCHER"
    printf '%s\n' "$RC_END"
  } >> "$RC_FILE"
  info "Installed launcher '$ALIAS_NAME' in $RC_FILE"

  # summary
  echo
  printf '%s\n' "${BOLD}Setup complete.${RESET}"
  printf '  launcher : %s\n' "$ALIAS_NAME"
  printf '  config   : %s\n' "$CONFIG_DIR"
  printf '  endpoint : %s\n' "$BASE_URL"
  printf '  api key  : %s (len %s, stored only in settings.json)\n' "****${API_KEY: -4}" "${#API_KEY}"
  echo
  printf '%s\n' "${BOLD}Next steps${RESET}"
  printf '  1. Reload your shell:   %s\n' "exec zsh   # or: source $RC_FILE"
  printf '  2. Go to a PERSONAL repo and start it:\n'
  printf '       cd ~/dev/repo/github/SuprayanY/wedding-manager && %s\n' "$ALIAS_NAME"
  printf '  3. If asked "Do you want to use this API key?" -> Yes\n'
  printf '  4. Run %s inside the session and verify:%s\n' "/status" ""
  printf '       Auth token:         ANTHROPIC_AUTH_TOKEN\n'
  printf '       Anthropic base URL: %s\n' "$BASE_URL"
  printf '       Setting sources:    User settings only\n'
  printf '       (no "Enterprise managed settings (remote)", no Organization)\n'
  echo
  printf '%s\n' "${DIM}Ground rules: use $ALIAS_NAME only in personal repos — company code must stay on the company account. Uninstall anytime with: ./setup.sh --remove${RESET}"
}

# --- remove --------------------------------------------------------------------
cmd_remove() {
  header
  local rc found=0 dir=""
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.bash_profile" "$HOME/.profile"; do
    if [ -f "$rc" ] && grep -qF "$RC_BEGIN" "$rc"; then
      # capture the config dir before removing the block
      if [ -z "$dir" ]; then
        dir=$(grep -A6 -F "$RC_BEGIN" "$rc" \
              | sed -n 's/.*CLAUDE_CONFIG_DIR="\([^"]*\)".*/\1/p' | head -n1)
        dir=${dir//\$HOME/$HOME}
      fi
      remove_rc_block "$rc"
      info "Removed launcher block from $rc"
      found=1
    fi
  done
  [ "$found" -eq 1 ] || warn "No managed claude-glm block found in any shell rc file."

  if [ -n "$dir" ] && [ -d "$dir" ]; then
    echo
    printf '%s' "${BOLD}Also delete the config directory and its sessions/plugins?${RESET} ${DIM}$dir${RESET} [no]: "
    read -r REPLY </dev/tty 2>/dev/null || read -r REPLY || true
    case ${REPLY:-no} in
      y|Y|yes|YES)
        rm -rf "$dir"
        info "Deleted $dir"
        ;;
      *) info "Kept $dir (you can delete it manually later)" ;;
    esac
  fi
  info "Done. Reload your shell: exec zsh"
}

# --- main ----------------------------------------------------------------------
case "${1:-init}" in
  init)          cmd_init ;;
  --remove|-r)   cmd_remove ;;
  -h|--help)     usage ;;
  *)             usage; exit 1 ;;
esac
