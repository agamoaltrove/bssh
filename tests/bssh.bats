#!/usr/bin/env bats
load 'test_helper'

@test "deduce_method key only" {
  run deduce_method "/path/key" ""
  [ "$status" -eq 0 ]
  [ "$output" = "key" ]
}

@test "deduce_method password only" {
  run deduce_method "" "secret"
  [ "$status" -eq 0 ]
  [ "$output" = "password" ]
}

@test "deduce_method passphrase" {
  run deduce_method "/path/key" "secret"
  [ "$status" -eq 0 ]
  [ "$output" = "passphrase" ]
}

@test "deduce_method manual" {
  run deduce_method "" ""
  [ "$status" -eq 0 ]
  [ "$output" = "manual" ]
}

@test "load_default_ssh_options reads port from __defaults__" {
  load_default_ssh_options
  [ "$DEFAULT_PORT" = "2222" ]
  [ "${DEFAULT_SSH_OPTIONS[0]}" = "-o StrictHostKeyChecking=no" ]
}

@test "load_host inherits default port when omitted" {
  load_default_ssh_options
  load_host host1
  [ "$HOST_PORT" = "2222" ]
}

@test "load_host uses explicit port" {
  load_host host2
  [ "$HOST_PORT" = "2200" ]
}

@test "load_host jump port falls back to default" {
  load_default_ssh_options
  load_host hostjump
  [ "${HOST_JUMP_PORT[0]}" = "2222" ]
}

@test "build_proxy_command single jump contains port and host" {
  load_default_ssh_options
  load_host hostjump
  run build_proxy_command
  [ "$status" -eq 0 ]
  [[ "$output" == *"jump.example.com"* ]]
  [[ "$output" == *"-W %h:%p"* ]]
}

@test "build_proxy_command multi jump contains both hosts" {
  load_default_ssh_options
  load_host hostmulti
  run build_proxy_command
  [ "$status" -eq 0 ]
  [[ "$output" == *"jump1.example.com"* ]]
  [[ "$output" == *"jump2.example.com"* ]]
}

@test "build_proxy_command empty when no jumps" {
  load_default_ssh_options
  load_host host1
  run build_proxy_command
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "merge_ssh_options overrides by name" {
  DEFAULT_SSH_OPTIONS=("-o Foo=bar")
  merge_ssh_options "-o Foo=baz"
  [ "${SSH_OPTION_ARGS[0]}" = "-o Foo=baz" ]
  [ "${#SSH_OPTION_ARGS[@]}" -eq 1 ]
}
