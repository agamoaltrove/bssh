#!/usr/bin/env bats
load 'test_helper'

setup() {
  export BSSH_NO_MAIN=1
  export HOSTS_FILE="${BATS_TEST_DIRNAME}/fixtures/hosts.yml"
  source "${BATS_TEST_DIRNAME}/../bscp.sh"
  MOCKBIN="$BATS_TMPDIR/mockbin"
  mkdir -p "$MOCKBIN"
  cat > "$MOCKBIN/scp" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
  chmod +x "$MOCKBIN/scp"
  export PATH="$MOCKBIN:$PATH"
}

@test "scp_key passes port" {
  load_default_ssh_options
  run scp_key alice a b 2222 ~/.ssh/id_rsa ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"-P 2222"* ]]
}

@test "scp_key_passphrase passes port" {
  SSH_OPTION_ARGS=()
  run scp_key_passphrase alice a b 2222 ~/.ssh/id_rsa secret ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"-P 2222"* ]]
}

@test "scp_manual omits port when empty" {
  load_default_ssh_options
  run scp_manual alice a b "" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"-o Port="* ]]
}
