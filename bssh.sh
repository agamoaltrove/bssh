#!/bin/bash
### bssh - SSH wrapper with yq/fzf/sshpass support (multi-jump)
### author: Agamo
set -o pipefail

bssh_version="1.0.0"

HOSTS_FILE="$HOME/.bssh.yml"

# SSH options: globali from defaults.ssh_options + per-host .ssh_options
DEFAULT_SSH_OPTIONS=()
DEFAULT_PORT=""
HOST_SSH_OPTIONS=()
SSH_OPTION_ARGS=()

export FZF_DEFAULT_OPTS="\
--height 50% \
--layout=reverse \
--border \
--header=HEADER_HERE \
--ellipsis=... \
--keep-right \
--color=bg+:#53565c,info:#BDBB72,border:#6B6B6B,\
spinner:#98BC99,hl:#719872,fg:#D9D9D9,header:#719872,\
fg+:#D9D9D9,pointer:#E12672,marker:#E17899,prompt:#98BEDE,\
hl+:#98BC99"

show_version() {
  printf 'version %s\n' "$bssh_version"
}

# --- Utility ---
die() {
  echo "error: $*" >&2
  exit 1
}

die_usage() {
  echo "error: $*" >&2
  show_usage
  exit 1
}

show_usage() {
  printf "Usage: %bbssh%b [help]%b\n" "\033[1;32m" "\033[1;33m" "\033[0m"
  printf "    'bssh help' for more information\n"
}

show_help() {
  cat << HELP
bssh - author: Agamo - $(show_version)
SSH wrapper with yq/fzf/sshpass support (multi-jump)

Usage: bssh [help]

Authentication is defined in .bssh.yml via nested 'auth' blocks:
  key        SSH with private key (auth.key)
  passphrase SSH with private key + passphrase (auth.key + auth.pass)
  password   SSH with password (auth.pass)
  manual     SSH with interactive password prompt (no auth fields)

Jump hosts are defined via a nested 'jump' list, each with its own 'auth'.
Multiple jumps are chained (multi-bastion).

Host file ($HOME/.bssh.yml) format:
  - id: myserver
    user: root
    host: 192.168.1.100
    port: 22
    auth:
      key: /path/to/key
      pass: <password_or_passphrase>
    jump:
      - user: jumpuser
        host: jump1.example.com
        port: 22
        auth:
          key: /path/to/jump_key
      - user: jumpuser2
        host: jump2.example.com
        port: 2222
        auth:
          pass: <jump_password>
    note: "description"

The auth method is deduced automatically from the fields present:
  - only key          -> key
  - only pass         -> password
  - key + pass        -> passphrase
  - neither           -> manual

Dependencies: yq, fzf, sshpass

  bssh help, --help, -h               show this help text
HELP
}

# --- Dependency checks ---
check_deps() {
  local missing=0
  for cmd in yq fzf; do
    command -v "$cmd" &>/dev/null || { echo "Missing dependency: $cmd"; missing=1; }
  done
  command -v sshpass &>/dev/null || echo "warning: sshpass not found (needed for password/passphrase/jump methods)" >&2
  [ "$missing" -eq 1 ] && exit 1
}

# --- Host file management ---
validate_hosts_file() {
  [ -f "$HOSTS_FILE" ] || die "File $HOSTS_FILE not found"

  yq -e . "$HOSTS_FILE" >/dev/null 2>&1 || die "Invalid YAML in $HOSTS_FILE"

  yq '.[] | select(.id==null)' "$HOSTS_FILE" | grep -q . && \
    die "All entries must have an 'id' field"

  local dup_ids
  dup_ids=$(yq -r '.[].id' "$HOSTS_FILE" | sort | uniq -d)
  [ -n "$dup_ids" ] && die "Duplicate IDs: $dup_ids"

  # Warning if hosts file is not protected with 600 permissions
  local perms
  perms=$(stat -c '%a' "$HOSTS_FILE" 2>/dev/null)
  [ "$perms" != "600" ] && echo "warning: $HOSTS_FILE has permissions $perms; consider chmod 600" >&2

  # Warning for hosts storing auth.pass in plain text
  local plain_ids
  plain_ids=$(yq -r '.[] | select(.auth.pass != null) | select((.auth.pass | tostring | startswith("base64:") | not) and (.auth.pass | tostring | startswith("pass:") | not)) | .id' "$HOSTS_FILE" 2>/dev/null)
  if [ -n "$plain_ids" ]; then
    echo "warning: hosts with auth.pass in plain text: $plain_ids" >&2
  fi
}

# Create .bssh.yml with examples if missing. Returns 0 if the file already existed,
# 1 if it was just created (caller should exit).
init_hosts_file() {
  [ -f "$HOSTS_FILE" ] && return 0

  cat > "$HOSTS_FILE" << 'EOF'
# bssh / bscp - Definizioni host
# Modifica questo file con i tuoi host. Gli esempi sotto sono commentati.
#
# Autenticazione (dedotta automaticamente dai campi presenti):
#   auth.key solo        -> key
#   auth.pass solo       -> password
#   auth.key + auth.pass -> passphrase
#   nessuno              -> manual (prompt interattivo)
#
# Password oscurate:
#   auth.pass: base64:<valore codificato in base64>
#   auth.pass: pass:<nome-voce>  (letto da `pass show <nome>`, password store)
#
# Opzioni SSH globali (elemento speciale __defaults__):
#   ssh_options applicate a tutti gli host, sovrascrivibili per-host.
#
# Permessi consigliati: chmod 600 $HOME/.bssh.yml

- id: __defaults__
  ssh_options:
    - "-o StrictHostKeyChecking=no"
    - "-o UserKnownHostsFile=/dev/null"

- id: esempio-chiave
  user: root
  host: 192.168.1.10
  port: 22
  auth:
    key: ~/.ssh/id_ed25519
  note: "Accesso con chiave SSH"

- id: esempio-password
  user: admin
  host: 192.168.1.20
  auth:
    pass: "lapassword"
  note: "Accesso con password (in chiaro)"

- id: esempio-passphrase
  user: deploy
  host: 10.0.0.5
  port: 2222
  auth:
    key: ~/.ssh/id_ed25519
    pass: "lapassphrase"
  note: "Chiave con passphrase"

- id: esempio-manuale
  user: ospite
  host: 10.0.0.6
  auth: {}
  note: "Prompt interattivo (nessuna password salvata)"

- id: esempio-jump
  user: root
  host: 10.0.0.50
  auth:
    key: ~/.ssh/id_ed25519
  jump:
    - user: bastion
      host: 10.0.0.1
      port: 22
      auth:
        key: ~/.ssh/id_ed25519_bastion
  note: "Accesso tramite jump host"

- id: esempio-base64
  user: root
  host: 10.0.0.60
  auth:
    pass: base64:cGFzc3dvcmQxMjM=
  note: "Password codificata in base64 (echo cGFzc3dvcmQxMjM= | base64 -d)"

- id: esempio-passstore
  user: root
  host: 10.0.0.70
  auth:
    pass: pass:bssh/esempio
  note: "Password letta da `pass show bssh/esempio`"
EOF
  chmod 600 "$HOSTS_FILE"
  echo "Creato $HOSTS_FILE con esempi. Modificalo e rilancia bssh." >&2
  return 1
}

list_hosts() {
  yq -r '.[] | select(.id != "__defaults__") | [.id, .user + "@" + .host, .note // ""] | @tsv' "$HOSTS_FILE"
}

select_host() {
  list_hosts |
  awk -F'\t' '{
    printf "%s\t%-30s %-30s\t%s\n", $1, $1, $2, $3
  }' |
  fzf \
    --header "Select host" \
    --with-nth=2 --delimiter=$'\t' \
    --preview="echo {3}" \
    --preview-window=down:3:wrap \
    | cut -f1
}

get_host_field() {
  local id=$1 field=$2
  yq -r '.[] | select(.id=="'"$id"'") | .'"$field"' // "null"' "$HOSTS_FILE"
}

# Deduce auth method from presence of key/pass fields
deduce_method() {
  local has_key="$1" has_pass="$2"
  if [ -n "$has_key" ] && [ -n "$has_pass" ]; then
    echo "passphrase"
  elif [ -n "$has_key" ]; then
    echo "key"
  elif [ -n "$has_pass" ]; then
    echo "password"
  else
    echo "manual"
  fi
}

# Resolve an auth secret that may be:
#   - plain text           -> returned as-is
#   - base64:<value>       -> base64-decoded
#   - pass:<entry>         -> read from the `pass` password store
resolve_secret() {
  local value="$1"
  case "$value" in
    base64:*)
      echo "${value#base64:}" | base64 -d 2>/dev/null || true
      ;;
    pass:*)
      pass show "${value#pass:}" 2>/dev/null || true
      ;;
    *)
      echo "$value"
      ;;
  esac
}

# Extract the name of an ssh option from a string like "-o StrictHostKeyChecking=no"
# or "-o StrictHostKeyChecking no". Returns only "StrictHostKeyChecking".
extract_opt_name() {
  local opt="$1"
  opt="${opt#-o }"
  opt="${opt%%=*}"
  opt="${opt%% *}"
  echo "$opt"
}

# Load global ssh_options from defaults.ssh_options (run once).
load_default_ssh_options() {
  DEFAULT_SSH_OPTIONS=()
  DEFAULT_PORT=""
  # Cerca l'elemento speciale con id "__defaults__" per le opzioni globali
  if yq -e '.[] | select(.id == "__defaults__")' "$HOSTS_FILE" >/dev/null 2>&1; then
    while IFS= read -r opt; do
      [ -n "$opt" ] && DEFAULT_SSH_OPTIONS+=("$opt")
    done < <(yq -r '.[] | select(.id == "__defaults__") | .ssh_options[]' "$HOSTS_FILE" 2>/dev/null)
    DEFAULT_PORT=$(yq -r '.[] | select(.id == "__defaults__") | .port // ""' "$HOSTS_FILE" 2>/dev/null)
    [ "$DEFAULT_PORT" = "null" ] && DEFAULT_PORT=""
  fi
  return 0
}

# Build SSH_OPTION_ARGS by merging default + per-host options.
# Per-host options override defaults with the same name.
merge_ssh_options() {
  SSH_OPTION_ARGS=()
  declare -A seen=()
  local opt name
  # Defaults first
  for opt in "${DEFAULT_SSH_OPTIONS[@]}"; do
    name=$(extract_opt_name "$opt")
    seen["$name"]=1
    SSH_OPTION_ARGS+=("$opt")
  done
  # Then per-host (override same key)
  for opt in "$@"; do
    [ -z "$opt" ] && continue
    name=$(extract_opt_name "$opt")
    if [ -n "${seen[$name]}" ]; then
      # Sostituisce l'entry esistente con lo stesso nome
      local i
      for ((i=0; i<${#SSH_OPTION_ARGS[@]}; i++)); do
        if [ "$(extract_opt_name "${SSH_OPTION_ARGS[$i]}")" = "$name" ]; then
          SSH_OPTION_ARGS[$i]="$opt"
          break
        fi
      done
    else
      seen["$name"]=1
      SSH_OPTION_ARGS+=("$opt")
    fi
  done
}

load_host() {
  local id=$1
  IFS=$'\x1f' read -r HOST_USER HOST_HOST HOST_PORT \
    HOST_AUTH_KEY HOST_AUTH_PASS \
    HOST_NOTE < <(
    yq -r '.[] | select(.id=="'"$id"'") |
      [.user, .host, (.port),
       (.auth.key // ""), (.auth.pass // ""),
       (.note // "")] | join("\u001f")' "$HOSTS_FILE"
  )

  [ "$HOST_USER" == "null" ] && die "user field cannot be null"
  [ "$HOST_HOST" == "null" ] && die "host field cannot be null"

  # Port: if omitted in host, use DEFAULT_PORT (from __defaults__); if empty, ssh uses its default
  if [ "$HOST_PORT" = "null" -o -z "$HOST_PORT" ]; then
    [ -n "$DEFAULT_PORT" ] && HOST_PORT="$DEFAULT_PORT" || HOST_PORT=""
  fi

  # Resolve auth.pass (plain / base64: / pass:)
  HOST_AUTH_PASS=$(resolve_secret "$HOST_AUTH_PASS")

  HOST_METHOD=$(deduce_method "$HOST_AUTH_KEY" "$HOST_AUTH_PASS")

  # Jump hosts (multi-jump support)
  HOST_JUMP_USER=()
  HOST_JUMP_HOST=()
  HOST_JUMP_PORT=()
  HOST_JUMP_AUTH_KEY=()
  HOST_JUMP_AUTH_PASS=()
  HOST_JUMP_METHOD=()

  local jump_count
  jump_count=$(yq -r '.[] | select(.id=="'"$id"'") | (.jump // []) | length' "$HOSTS_FILE")

  if [ "$jump_count" -gt 0 ]; then
    local i
    for ((i=0; i<jump_count; i++)); do
      local ju jh jp jk jpass
      ju=$(yq -r '.[] | select(.id=="'"$id"'") | .jump['"$i"'].user // ""' "$HOSTS_FILE")
      jh=$(yq -r '.[] | select(.id=="'"$id"'") | .jump['"$i"'].host // ""' "$HOSTS_FILE")
       jp=$(yq -r '.[] | select(.id=="'"$id"'") | .jump['"$i"'].port // ""' "$HOSTS_FILE")
       [ "$jp" = "null" ] && jp=""
       [ -z "$jp" ] && [ -n "$DEFAULT_PORT" ] && jp="$DEFAULT_PORT"
      jk=$(yq -r '.[] | select(.id=="'"$id"'") | .jump['"$i"'].auth.key // ""' "$HOSTS_FILE")
      jpass=$(yq -r '.[] | select(.id=="'"$id"'") | .jump['"$i"'].auth.pass // ""' "$HOSTS_FILE")
      jpass=$(resolve_secret "$jpass")

      [ -z "$jh" ] && die "jump $((i+1)) host cannot be null"
      [ -z "$ju" ] && die "jump $((i+1)) user cannot be null"

      HOST_JUMP_USER+=("$ju")
      HOST_JUMP_HOST+=("$jh")
      HOST_JUMP_PORT+=("$jp")
      HOST_JUMP_AUTH_KEY+=("$jk")
      HOST_JUMP_AUTH_PASS+=("$jpass")
      HOST_JUMP_METHOD+=("$(deduce_method "$jk" "$jpass")")
    done
  fi

  # SSH options per-host (si uniscono alle default, sovrascrivendole)
  HOST_SSH_OPTIONS=()
  if yq -e '.[] | select(.id=="'"$id"'") | .ssh_options' "$HOSTS_FILE" >/dev/null 2>&1; then
    while IFS= read -r opt; do
      [ -n "$opt" ] && HOST_SSH_OPTIONS+=("$opt")
    done < <(yq -r '.[] | select(.id=="'"$id"'") | .ssh_options[]' "$HOSTS_FILE" 2>/dev/null)
  fi
  merge_ssh_options "${HOST_SSH_OPTIONS[@]}"
}

# --- SSH connection methods ---
ssh_key() {
  local ssh_user="$1" ssh_host="$2" ssh_port="$3" ssh_key="$4" ssh_proxy="$5"
  local ssh_args=(-t -i "$ssh_key")
  [ -n "$ssh_port" ] && ssh_args+=(-p "$ssh_port")
  ssh_args+=("${SSH_OPTION_ARGS[@]}")
  [ -n "$ssh_proxy" ] && ssh_args+=(-o "ProxyCommand=$ssh_proxy")
  ssh "${ssh_args[@]}" "$ssh_user@$ssh_host"
}

ssh_key_passphrase() {
  local ssh_user="$1" ssh_host="$2" ssh_port="$3" ssh_key="$4" ssh_secret="$5" ssh_proxy="$6"
  local ssh_args=(-t -i "$ssh_key")
  [ -n "$ssh_port" ] && ssh_args+=(-p "$ssh_port")
  ssh_args+=("${SSH_OPTION_ARGS[@]}")
  [ -n "$ssh_proxy" ] && ssh_args+=(-o "ProxyCommand=$ssh_proxy")
  sshpass -d 9 -P passphrase \
    ssh "${ssh_args[@]}" "$ssh_user@$ssh_host" \
    9<<<"$ssh_secret"
}

ssh_password() {
  local ssh_user="$1" ssh_host="$2" ssh_port="$3" ssh_secret="$4" ssh_proxy="$5"
  local ssh_args=(-t)
  [ -n "$ssh_port" ] && ssh_args+=(-p "$ssh_port")
  ssh_args+=("${SSH_OPTION_ARGS[@]}")
  [ -n "$ssh_proxy" ] && ssh_args+=(-o "ProxyCommand=$ssh_proxy")
  if [ "${BSSH_DEBUG:-0}" = "1" ]; then
    echo "[bssh debug] ssh -v -t ${SSH_OPTION_ARGS[*]} $ssh_user@$ssh_host -p $ssh_port (password: ${ssh_secret:0:1}***)" >&2
    sshpass -d 9 \
      ssh -v "${ssh_args[@]}" "$ssh_user@$ssh_host" \
      9<<<"$ssh_secret"
  else
    sshpass -d 9 \
      ssh "${ssh_args[@]}" "$ssh_user@$ssh_host" \
      9<<<"$ssh_secret"
  fi
}

ssh_manual() {
  local ssh_user="$1" ssh_host="$2" ssh_port="$3" ssh_proxy="$4"
  local ssh_args=(-t)
  [ -n "$ssh_port" ] && ssh_args+=(-p "$ssh_port")
  ssh_args+=("${SSH_OPTION_ARGS[@]}")
  [ -n "$ssh_proxy" ] && ssh_args+=(-o "ProxyCommand=$ssh_proxy")
  ssh "${ssh_args[@]}" "$ssh_user@$ssh_host"
}

# Build a nested ProxyCommand chain from the jump list.
# The first jump in the list is the outermost (closest to your machine),
# the last jump is the innermost (closest to the target).
build_proxy_command() {
  local n=${#HOST_JUMP_HOST[@]}
  [ "$n" -eq 0 ] && return 0

  local proxy_cmd=""
  local i

  for ((i=0; i<n; i++)); do
    local j_user="${HOST_JUMP_USER[$i]}"
    local j_host="${HOST_JUMP_HOST[$i]}"
    local j_port="${HOST_JUMP_PORT[$i]}"
    local j_method="${HOST_JUMP_METHOD[$i]}"
    local j_key="${HOST_JUMP_AUTH_KEY[$i]}"
    local j_pass="${HOST_JUMP_AUTH_PASS[$i]}"

    # The jump password/passphrase is passed via SSHPASS
    # (variable inherited by the sh running the ProxyCommand), so sshpass
    # can read it even inside the nested tunnel.
    local new_cmd=""

    case "$j_method" in
       password)
         new_cmd="env SSHPASS=\"${j_pass}\" sshpass -e ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=yes -o KbdInteractiveAuthentication=yes -o PreferredAuthentications=password,keyboard-interactive${j_port:+ -p \"${j_port}\"} -W %h:%p ${j_user}@${j_host}"
        [ -n "$proxy_cmd" ] && new_cmd="${new_cmd/ -W %h:%p/ -o ProxyCommand='PLACEHOLDER' -W %h:%p}"
        [ -n "$proxy_cmd" ] && new_cmd="${new_cmd/PLACEHOLDER/$proxy_cmd}"
        ;;
       key)
         new_cmd="ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey -i \"${j_key}\"${j_port:+ -p \"${j_port}\"} -W %h:%p ${j_user}@${j_host}"
        [ -n "$proxy_cmd" ] && new_cmd="${new_cmd/ -W %h:%p/ -o ProxyCommand='PLACEHOLDER' -W %h:%p}"
        [ -n "$proxy_cmd" ] && new_cmd="${new_cmd/PLACEHOLDER/$proxy_cmd}"
        ;;
       passphrase)
         new_cmd="env SSHPASS=\"${j_pass}\" sshpass -P passphrase -e ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey -i \"${j_key}\"${j_port:+ -p \"${j_port}\"} -W %h:%p ${j_user}@${j_host}"
        [ -n "$proxy_cmd" ] && new_cmd="${new_cmd/ -W %h:%p/ -o ProxyCommand='PLACEHOLDER' -W %h:%p}"
        [ -n "$proxy_cmd" ] && new_cmd="${new_cmd/PLACEHOLDER/$proxy_cmd}"
        ;;
       manual)
         new_cmd="ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password,keyboard-interactive${j_port:+ -p \"${j_port}\"} -W %h:%p ${j_user}@${j_host}"
        [ -n "$proxy_cmd" ] && new_cmd="${new_cmd/ -W %h:%p/ -o ProxyCommand='PLACEHOLDER' -W %h:%p}"
        [ -n "$proxy_cmd" ] && new_cmd="${new_cmd/PLACEHOLDER/$proxy_cmd}"
        ;;
    esac

    proxy_cmd="$new_cmd"
  done

  echo "$proxy_cmd"
}

# --- Main ---
main() {
  case "${1:-}" in
    help|--help|-h) show_help; exit 0 ;;
    version|--version|-V) show_version; exit 0 ;;
  esac

  # Initialize .bssh.yml if missing
  init_hosts_file || exit 0

  check_deps
  validate_hosts_file
  load_default_ssh_options

  case "${1:-}" in
    info)
      [ -z "$2" ] && die_usage "info requires a host id"
      load_host "$2"
      echo "user:      $HOST_USER"
      echo "host:      $HOST_HOST"
      echo "port:      $HOST_PORT"
      echo "method:    $HOST_METHOD (deduced from auth fields)"
      [ -n "$HOST_AUTH_KEY" ]    && echo "auth.key:  $HOST_AUTH_KEY"
      [ -n "$HOST_AUTH_PASS" ]   && echo "auth.pass: **** (length: ${#HOST_AUTH_PASS})"
      local jn=${#HOST_JUMP_HOST[@]}
      if [ "$jn" -gt 0 ]; then
        local i
        for ((i=0; i<jn; i++)); do
          echo "jump $((i+1)):"
          echo "  user:     ${HOST_JUMP_USER[$i]}"
          echo "  host:     ${HOST_JUMP_HOST[$i]}"
          echo "  port:     ${HOST_JUMP_PORT[$i]}"
          echo "  method:   ${HOST_JUMP_METHOD[$i]} (deduced)"
          [ -n "${HOST_JUMP_AUTH_KEY[$i]}" ]    && echo "  auth.key: ${HOST_JUMP_AUTH_KEY[$i]}"
          [ -n "${HOST_JUMP_AUTH_PASS[$i]}" ]   && echo "  auth.pass: **** (length: ${#HOST_JUMP_AUTH_PASS[$i]})"
        done
      fi
      [ -n "$HOST_NOTE" ] && echo "note:      $HOST_NOTE"
      exit 0 ;;
  esac

  local target_id
  target_id=$(select_host)
  [ -z "$target_id" ] && exit 0

  # --- Colored high-contrast header before connecting ---
  HEADER_STYLES=(
    "44;97"   # blue background, bright white text
    "42;30"   # green background, black text
    "46;30"   # cyan background, black text
    "45;97"   # magenta background, bright white text
    "43;30"   # yellow background, black text
    "41;97"   # red background, bright white text
    "47;30"   # white background, black text
    "104;97"  # bright blue background, bright white text
    "102;30"  # bright green background, black text
    "106;30"  # bright cyan background, black text
  )
  HEADER_STYLE="${HEADER_STYLES[$(( RANDOM % ${#HEADER_STYLES[@]} ))]}"

  echo
  printf "\033[${HEADER_STYLE}m  ◆ [host]: %s  \033[0m\n" "$target_id"
  echo

  load_host "$target_id"
  # Show connection path before establishing the session (useful when several
  # manual/password prompts will appear for multi-jump chains).
  local jn=${#HOST_JUMP_HOST[@]}
  if [ "$jn" -gt 0 ]; then
    local path_parts=()
    local i
    for ((i=0; i<jn; i++)); do
      path_parts+=("${HOST_JUMP_USER[$i]}@${HOST_JUMP_HOST[$i]}:${HOST_JUMP_PORT[$i]}")
    done
    path_parts+=("${HOST_USER}@${HOST_HOST}:${HOST_PORT}")
    local path=""
    local first=1
    for part in "${path_parts[@]}"; do
      if [ "$first" -eq 1 ]; then
        path="$part"
        first=0
      else
        path="$path > $part"
      fi
    done
    echo "  ➤ Route: $path"
    echo
  fi

  local proxy_cmd=""
  if [ "$jn" -gt 0 ]; then
    proxy_cmd=$(build_proxy_command)
  fi

  case $HOST_METHOD in
    key)
      ssh_key "$HOST_USER" "$HOST_HOST" "$HOST_PORT" "$HOST_AUTH_KEY" "$proxy_cmd"
      ;;
    passphrase)
      ssh_key_passphrase "$HOST_USER" "$HOST_HOST" "$HOST_PORT" "$HOST_AUTH_KEY" "$HOST_AUTH_PASS" "$proxy_cmd"
      ;;
    password)
      ssh_password "$HOST_USER" "$HOST_HOST" "$HOST_PORT" "$HOST_AUTH_PASS" "$proxy_cmd"
      ;;
    manual)
      ssh_manual "$HOST_USER" "$HOST_HOST" "$HOST_PORT" "$proxy_cmd"
      ;;
    *)           die "Unknown method: $HOST_METHOD" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" && "${BSSH_NO_MAIN:-0}" != "1" ]]; then main "$@"; fi
