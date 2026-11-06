#!/usr/bin/env bash
export BSSH_NO_MAIN=1
source "${BATS_TEST_DIRNAME}/../bssh.sh"
export HOSTS_FILE="${BATS_TEST_DIRNAME}/fixtures/hosts.yml"