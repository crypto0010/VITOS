# /etc/profile.d/vitos-shell-tap.sh
# Sourced into every interactive bash/zsh login.
[ -z "${PS1:-}" ] && return 0
[ -S /run/vitos/bus.sock ] || return 0

__vitos_emit() {
  local cmd="$1"
  local user="$(id -un)"
  local ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","type":"shell_cmd","student_id":"%s","session_id":"%s","cmd":%s}\n' \
    "$ts" "$user" "${VITOS_SESSION_ID:-${user}-$$}" \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | socat - UNIX-CONNECT:/run/vitos/bus.sock 2>/dev/null || true
}

if [ -n "${BASH_VERSION:-}" ]; then
  trap '__vitos_emit "$BASH_COMMAND"' DEBUG
elif [ -n "${ZSH_VERSION:-}" ]; then
  preexec() { __vitos_emit "$1"; }
fi
