# 🔑 bssh / bscp - SSH and SCP wrappers with multi-host support

For full details, see [MANUAL.md](MANUAL.md).

**bssh** and **bscp** are lightweight **bash** wrappers that let you manage SSH/SCP connections to many hosts from a single YAML config file.
`bssh` connects interactively via an `fzf` chooser, picking the right authentication method for each host.
`bscp` copies files to and from remote hosts using the same definitions — prefix remote paths with `remote:`.

A deliberately minimalist tool that stays true to the shell philosophy:
config in, connection out, composable with your shell workflow.

No JSON, no databases, no npm install — just bash, yq, fzf, and sshpass.

## Features

- **Multi-host config** — store all your hosts in `~/.bssh.yml` (YAML)
- **Interactive selection** — fuzzy-find a host with `fzf` before connecting
- **Multiple auth methods** — `key`, `passphrase`, `password`, `manual`
- **Jump host support** — tunnel through one or more bastions (multi-jump)
- **SCP wrapper** — `bscp` uploads/downloads using the same host definitions
- **No dependencies beyond the essentials** — bash, yq, fzf, sshpass

## Requirements

| Tool | Minimum |
|------|---------|
| bash | 4.0+ |
| yq | any recent version (mikefarah/yq) |
| fzf | any recent version |
| sshpass | needed for password/passphrase/jump methods |

That's it. Every system with bash has most of these; the rest are a single `apt install` away.

## Installation

```bash
# 1. Get the scripts (clone or download a release)
git clone <repo-url> ~/bssh
# or download the release archive and extract it where you prefer
cd ~/bssh

# 2. Make executable
chmod +x bssh.sh bscp.sh

# 3a. Symlink into PATH (or whatever path you use for your tools)
ln -sf "$PWD/bssh.sh" ~/.local/bin/bssh
ln -sf "$PWD/bscp.sh" ~/.local/bin/bscp

# 3b. Or add aliases to your .bashrc
echo "alias bssh='$PWD/bssh.sh'" >> ~/.bashrc
echo "alias bscp='$PWD/bscp.sh'" >> ~/.bashrc
```

Install dependencies (Debian/Ubuntu):

```bash
sudo apt install yq fzf sshpass
```

## Configuration

Host definitions live in `~/.bssh.yml` (YAML). Each entry supports the following fields:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Unique identifier shown in the host selector |
| `user` | yes | SSH username |
| `host` | yes | Hostname or IP address |
| `port` | no | SSH port of the target host (default: `22`, or `__defaults__.port` if set) |
| `auth` | no | Nested block with `key` and/or `pass` for target authentication |
| `jump` | no | List of jump hosts (bastions), each with its own `user`, `host`, `port` and `auth`. Multiple jumps are chained. |
| `note` | no | Free text description, shown in the selector |

### Authentication methods (deduced automatically)

The `auth` method is deduced from the fields present — no `method` field needed:

| Fields in `auth` | Method | Meaning |
|------------------|--------|---------|
| `key` only | `key` | SSH with private key |
| `pass` only | `password` | SSH with password |
| `key` + `pass` | `passphrase` | SSH with private key + passphrase |
| none | `manual` | Interactive password prompt |

### Jump host(s)

The `jump` list defines one or more bastion hosts (multi-jump). Each entry has its own `user`, `host`, `port` and `auth`, following the same deduction rules above.
Jumps are chained in list order: the first entry is the outermost hop (closest to your machine), the last entry is the innermost hop (closest to the target).

### Examples

```yaml
# Target: key, no jump
- id: web1
  user: deploy
  host: 192.168.1.10
  port: 2222
  auth:
    key: ~/.ssh/deploy_rsa
  note: "Web server"

# Target: password, jump: password (single bastion)
- id: app1
  user: root
  host: 10.0.0.5
  auth:
    pass: target-pass
  jump:
    - user: jump
      host: bastion.example.com
      port: 2222
      auth:
        pass: jump-pass
  note: "Reachable via bastion"

# Target: key, jump: key
- id: app2
  user: deploy
  host: 10.0.0.6
  auth:
    key: ~/.ssh/deploy_key
  jump:
    - user: jump
      host: bastion.example.com
      port: 2222
      auth:
        key: ~/.ssh/jump_key

# Target: password, jump: passphrase (key + passphrase)
- id: app3
  user: root
  host: 10.0.0.7
  auth:
    pass: target-pass
  jump:
    - user: jump
      host: bastion.example.com
      port: 2222
      auth:
        key: ~/.ssh/jump_key
        pass: jump-passphrase

# Target: key, jump: manual (interactive)
- id: app4
  user: deploy
  host: 10.0.0.9
  auth:
    key: ~/.ssh/deploy_key
  jump:
    - user: jump
      host: bastion.example.com
      port: 2222
```

### Multi-jump example (double bastion)

```yaml
# Target: key, two bastions in chain (outer → inner → target)
- id: db_via_double_bastion
  user: root
  host: 10.0.0.50
  auth:
    key: ~/.ssh/db_key
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

## Usage

### bssh — connect to a host

```bash
bssh                # select host with fzf and connect
bssh help           # full help
bssh info server1   # show host details (secrets masked)
bssh version        # show version
```

The `fzf` selector shows each host's `id`, `user@host`, and optional `note`.
Pick one and bssh connects using the deduced auth method — key, password, jump host(s), etc.

### bscp — copy files to/from a remote host

`bscp` is the SCP counterpart of `bssh`. It sources `bssh.sh` for the host list, so every host defined in `~/.bssh.yml` is available.

Remote paths must use the `remote:` prefix. At runtime, `remote:` is replaced with the selected host's address (`$HOST_HOST:`), so you don't have to type the hostname every time.

```bash
bscp ./file.txt remote:/tmp/          # local → remote
bscp remote:/var/log/syslog ./logs/   # remote → local
bscp ./www/ remote:/var/www/html/     # recursive directory upload
```

Rules:
- Exactly one argument must carry the `remote:` prefix; the other is a local path.
- You cannot copy directly between two remote hosts.
- Jump methods work with bssh; bscp uses the target auth directly (no jump support in bscp).

```bash
bscp help        # full help
bscp version     # show version
```

## Output examples

Host selector (`fzf`):

```
Select host
─────────────────────────────────────────────────
 web1               deploy@192.168.1.10   Web server
 app1               root@10.0.0.5         Reachable via bastion
 db_via_double...   root@10.0.0.50
─────────────────────────────────────────────────
```

After selecting `web1`, bssh prints a highlighted host line and, if jump hosts are configured, the connection route:

```
  ◆ [host]: web1

  ➤ Route: jump1@bastion1.corp.com:2222 > jump2@bastion2.corp.com:22 > root@10.0.0.50:22
```

The host line uses a random high-contrast color at every launch. The route line appears only when at least one jump host is defined, so you know the full path before any password prompts appear.

## How it works

- **Config**: `~/.bssh.yml` — plain YAML array of host objects
- **Selection**: `yq` reads the file, `awk` formats a TSV table, `fzf` lets you pick a host
- **Loading**: `load_host` extracts fields into `HOST_*` variables and deduces the auth method from the `auth` block fields (`key`/`pass`)
- **Connection**: dispatches to the right `ssh_*` function (`ssh_key`, `ssh_password`, `ssh_key_passphrase`, `ssh_manual`)
- **Jump**: when `jump` is set, `build_proxy_command` builds a nested `ProxyCommand` chain from all jump `auth` blocks, and the target SSH command tunnels through them
- **SCP**: `bscp.sh` sources `bssh.sh`, replaces `remote:` with the selected host, then calls `scp` with the matching auth method

## License

MIT — do whatever you want with it.
