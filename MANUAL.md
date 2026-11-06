# bssh / bscp — Command Manual

## bssh

Interactive SSH wrapper. Reads host definitions from `~/.bssh.yml`, presents an `fzf` selector, and connects using the deduced authentication method.

### Synopsis

```
bssh [help|--help|-h]
bssh [version|--version|-V]
bssh info <host_id>
bssh
```

### Commands

| Command                           | Description |
|-----------------------------------|-------------|
| `bssh`                            | Interactive mode — select a host via `fzf` and connect |
| `bssh help`                       | Print help text |
| `bssh version`                    | Print version number |
| `bssh info <host_id>`             | Show configuration details for a specific host (secrets masked) |

### Interactive flow

1. `check_deps` — verifies `yq` and `fzf` are installed (warns if `sshpass` is missing)
2. `validate_hosts_file` — parses `~/.bssh.yml`, checks YAML validity, ensures all entries have an `id`, rejects duplicate IDs
3. `list_hosts` / `select_host` — renders a TSV table of `(id, user@host, note?)`, pipes it through `awk` for alignment, then into `fzf` for interactive selection
4. `load_host <id>` — extracts the selected host's fields into global `HOST_*` variables, deduces the auth method from the `auth` block fields, loads any `jump` list
5. Dispatches to the appropriate `ssh_*` function based on the deduced `HOST_METHOD`
6. If `jump` is set, `build_proxy_command` builds a nested `ProxyCommand` chain from all jump `auth` blocks

### Environment

| Variable      | Default | Description |
|---------------|---------|-------------|
| `BSSH_DEBUG`  | `0`     | When set to `1`, the `password` method runs `ssh -v` and prints the first character of the password to stderr |

### Examples

```bash
bssh                    # pick a host and connect
bssh info server1       # inspect server1's settings
bssh --version          # 1.0.0
BSSH_DEBUG=1 bssh       # connect with verbose SSH output
```

---

## bscp

SCP wrapper. Sources `bssh.sh` for shared logic (host file parsing, host selection). Copies files to/from remote hosts using the same host definitions.

### Synopsis

```
bscp [help|--help|-h]
bscp [version|--version|-V]
bscp <local_path> remote:<remote_path>
bscp remote:<remote_path> <local_path>
```

### Commands

| Command                                           | Description |
|---------------------------------------------------|-------------|
| `bscp help`                                       | Print help text |
| `bscp version`                                    | Print version number |
| `bscp <local_path> remote:<remote_path>`          | Copy local file/directory to remote host |
| `bscp remote:<remote_path> <local_path>`          | Copy remote file/directory to local |

### Behaviour

- Exactly one argument must carry the `remote:` prefix; the other is a local path
- `remote:` is replaced at runtime with `$HOST_HOST:` (the selected host's address)
- The same interactive host selection flow as `bssh` is used
- SCP is always recursive (`-r`)
- Jump hosts are supported via `ProxyCommand` (same chain as `bssh`)

### Examples

```bash
bscp ./backup.sql remote:/tmp/          # upload
bscp remote:/var/log/syslog ./logs/     # download
bscp ./www/ remote:/var/www/html/       # recursive directory upload
```

---

## Configuration file: `~/.bssh.yml`

### Format

YAML array of host objects. Multi-line (block) style is recommended; nested `auth`/`jump` blocks are harder to read in single-line flow style.

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Unique identifier shown in the host selector |
| `user` | yes | SSH username |
| `host` | yes | Hostname or IP address |
| `port` | no | SSH port of the target host (default: `22`, or `__defaults__.port` if set) |
| `auth` | no | Nested block with `key` and/or `pass` for target authentication |
| `jump` | no | List of jump hosts (bastions), each with its own `user`, `host`, `port` and `auth`. Multiple jumps are chained. |
| `note` | no | Free-text description, shown in the host selector |

### Authentication methods (deduced automatically)

The `auth` method is deduced from the fields present — no explicit `method` field is needed:

| Fields in `auth` | Method | Meaning |
|------------------|--------|---------|
| `key` only | `key` | SSH with private key (`-i`) |
| `pass` only | `password` | SSH with password (via sshpass) |
| `key` + `pass` | `passphrase` | SSH with private key + passphrase (via sshpass) |
| none | `manual` | Interactive password prompt (no sshpass) |

`auth.pass` may also be encoded/obfuscated:
- `base64:<value>` — base64-decoded at runtime
- `pass:<entry>` — read from the `pass` password store (`pass show <entry>`)


### Jump host(s)

The `jump` list defines one or more bastion hosts (multi-jump). Each entry has its own `user`, `host`, `port` and `auth`, following the same deduction rules above.
Jumps are chained in list order: the first entry is the outermost hop (closest to your machine), the last entry is the innermost hop (closest to the target).

### Validation rules

- All entries must have a non-null `id`
- Duplicate `id` values are rejected
- `user` and `host` are required for every entry
- For each entry in `jump`: `user` and `host` are required
- `auth.key` requires the key file to exist
- `auth.pass` requires a non-empty value

### Examples

#### Multi-line

```yaml
- id: web
  user: deploy
  host: 192.168.1.10
  port: 2222
  auth:
    key: ~/.ssh/deploy_rsa
  note: "Web server"

- id: db
  user: root
  host: 192.168.1.20
  auth:
    pass: s3cret!
  note: "Database master"

- id: app_via_double_bastion
  user: deploy
  host: 10.0.0.5
  auth:
    key: ~/.ssh/deploy_key
  jump:
    - user: jump1
      host: bastion1.corp.com
      port: 2222
      auth:
        key: ~/.ssh/jump1_key
    - user: jump2
      host: bastion2.corp.com
      port: 22
      auth:
        pass: jump2_secret
```

#### Single-line (compact)

```yaml
- {id: web, user: deploy, host: 192.168.1.10, port: 2222, auth: {key: ~/.ssh/deploy_rsa}, note: "Web"}
- {id: db,  user: root,   host: 192.168.1.20, auth: {pass: s3cret!}, note: "DB"}
```

---

## Output examples

### Host selector (`fzf`)

```
Select host
─────────────────────────────────────────────────
 web1               deploy@192.168.1.10   Web server
 app1               root@10.0.0.5         Reachable via bastion
 db_via_double...   root@10.0.0.50
─────────────────────────────────────────────────
```

After selecting a host, bssh prints a highlighted header line with a random high-contrast color:

```
  ◆ [host]: web1
```

If jump hosts are configured, a route line follows:

```
  ➤ Route: jump1@bastion1.corp.com:2222 > jump2@bastion2.corp.com:22 > root@10.0.0.50:22
```

The route line appears only when at least one jump host is defined.

---

## Dependencies

| Tool       | Required | Notes |
|------------|----------|-------|
| `yq`       | yes      | YAML processing (https://github.com/mikefarah/yq) |
| `fzf`      | yes      | Interactive fuzzy selector (https://github.com/junegunn/fzf) |
| `sshpass`  | no*      | Non-interactive password authentication |

*`sshpass` is optional. Without it, only `key` and `manual` methods work. The script prints a warning at startup if `sshpass` is missing.

### Install (Debian/Ubuntu)

```bash
sudo apt install yq fzf sshpass
```

---

## Exit codes

| Code | Meaning |
|------|---------|
| 0    | Success |
| 1    | Generic error (missing dependency, invalid config, unknown method, etc.) |
| 130  | Interrupted by user (SIGINT / Ctrl-C, propagated from `fzf` or `ssh`) |

---

## Files

| Path | Purpose |
|------|---------|
| `~/.bssh.yml` | Host definitions (YAML) |
| `~/.ssh/`     | Default location for SSH keys referenced by `auth.key` |
