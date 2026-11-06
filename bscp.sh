#!/bin/bash
### bscp - SCP wrapper (sources bssh.sh for common logic)
### author: Agamo
set -o pipefail
set -f

bscp_version="1.0.0"

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/bssh.sh"

show_version() {
  printf 'version %s\n' "$bscp_version"
}

show_usage() {
  printf "Usage: %bbscp%b <local> remote:<remote>%b\n" "\033[1;32m" "\033[1;33m" "\033[0m"
  printf "       %bbscp%b remote:<remote> <local>%b\n" "\033[1;32m" "\033[1;33m" "\033[0m"
  printf "    'bscp help' for more information\n"
}

show_help() {
  cat << HELP
bscp - author: Agamo - $(show_version)
SCP wrapper (sources bssh.sh for host definitions)

Usage: bscp <local_path> remote:<remote_path>
       bscp remote:<remote_path> <local_path>

The 'remote:' prefix is replaced with the selected host address.
Uses the same host definitions and auth methods as bssh ($HOME/.bssh.yml).
Authentication is defined via nested 'auth' blocks with 'key' and/or 'pass'.

Examples:
  bscp ./file.txt remote:/tmp/
  bscp remote:/var/log/app.log ./logs/

Dependencies: yq, fzf, sshpass (inherited from bssh.sh)

  bscp help, --help, -h               show this help text
HELP
}

# --- SCP methods ---
scp_key() {
  local scp_user="$1" scp_target1="$2" scp_target2="$3" scp_port="$4" scp_key="$5" scp_proxy="$6"
  local scp_args=(-r -i "$scp_key")
  [ -n "$scp_port" ] && scp_args+=(-P "$scp_port")
  scp_args+=(-o User="$scp_user")
  scp_args+=("${SSH_OPTION_ARGS[@]}")
  [ -n "$scp_proxy" ] && scp_args+=(-o "ProxyCommand=$scp_proxy")
  scp "${scp_args[@]}" "$scp_target1" "$scp_target2"
}

scp_key_passphrase() {
  local scp_user="$1" scp_target1="$2" scp_target2="$3" scp_port="$4" scp_key="$5" scp_secret="$6" scp_proxy="$7"
  local scp_args=(-r -i "$scp_key")
  [ -n "$scp_port" ] && scp_args+=(-P "$scp_port")
  scp_args+=(-o User="$scp_user")
  scp_args+=("${SSH_OPTION_ARGS[@]}")
  [ -n "$scp_proxy" ] && scp_args+=(-o "ProxyCommand=$scp_proxy")
  SSHPASS="$scp_secret" sshpass -P passphrase -e \
    scp "${scp_args[@]}" "$scp_target1" "$scp_target2"
}

scp_manual() {
  local scp_user="$1" scp_target1="$2" scp_target2="$3" scp_port="$4" scp_proxy="$5"
  local scp_args=(-r -o User="$scp_user")
  [ -n "$scp_port" ] && scp_args+=(-o Port="$scp_port")
  scp_args+=("${SSH_OPTION_ARGS[@]}")
  [ -n "$scp_proxy" ] && scp_args+=(-o "ProxyCommand=$scp_proxy")
  scp "${scp_args[@]}" "$scp_target1" "$scp_target2"
}

scp_password() {
  local scp_user="$1" scp_target1="$2" scp_target2="$3" scp_port="$4" scp_secret="$5" scp_proxy="$6"
  local scp_args=(-r -o User="$scp_user")
  [ -n "$scp_port" ] && scp_args+=(-o Port="$scp_port")
  scp_args+=("${SSH_OPTION_ARGS[@]}")
  [ -n "$scp_proxy" ] && scp_args+=(-o "ProxyCommand=$scp_proxy")
  SSHPASS="$scp_secret" sshpass -e \
    scp "${scp_args[@]}" "$scp_target1" "$scp_target2"
}

# --- Main ---
main() {
  case "${1:-}" in
    help|--help|-h) show_help; exit 0 ;;
    version|--version|-V) show_version; exit 0 ;;
  esac

  local target1="${1:-}" target2="${2:-}"

  [ -z "$target1" ] || [ -z "$target2" ] && die_usage "missing argument(s)"

  [[ "$target1" != remote:* ]] && [[ "$target2" != remote:* ]] && die_usage "at least one path must be remote:"
  [[ "$target1" == remote:* ]] && [[ "$target2" == remote:* ]] && die "cannot copy between two remote hosts"

  validate_hosts_file
  load_default_ssh_options

  local target_id
  target_id=$(select_host)
  [ -z "$target_id" ] && exit 0

  load_host "$target_id"

  [[ "$target1" == remote:* ]] && target1="${target1/#remote:/$HOST_HOST:}"
  [[ "$target2" == remote:* ]] && target2="${target2/#remote:/$HOST_HOST:}"

  local proxy_cmd=""
  local jn=${#HOST_JUMP_HOST[@]}
  if [ "$jn" -gt 0 ]; then
    proxy_cmd=$(build_proxy_command)
  fi

  case $HOST_METHOD in
    key)        scp_key             "$HOST_USER" "$target1" "$target2" "$HOST_PORT" "$HOST_AUTH_KEY"     "$proxy_cmd" ;;
    passphrase) scp_key_passphrase  "$HOST_USER" "$target1" "$target2" "$HOST_PORT" "$HOST_AUTH_KEY"     "$HOST_AUTH_PASS" "$proxy_cmd" ;;
    password)   scp_password        "$HOST_USER" "$target1" "$target2" "$HOST_PORT" "$HOST_AUTH_PASS"     "$proxy_cmd" ;;
    manual)     scp_manual          "$HOST_USER" "$target1" "$target2" "$HOST_PORT"                      "$proxy_cmd" ;;
    *)          die "unsupported method for scp: $HOST_METHOD" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" && "${BSSH_NO_MAIN:-0}" != "1" ]]; then main "$@"; fi
