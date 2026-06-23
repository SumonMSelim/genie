# Server scripts

## `bootstrap-server.sh`

Interactive bootstrap for **Debian/Ubuntu** servers. Run as root (or with sudo). Prompts for each step so you can skip or customize.

**Supported:** Ubuntu 20.04 / 22.04 / 24.04 · Debian 11 / 12

### Steps (in order)

1. **Packages & Dependencies** — apt update/upgrade, base deps (curl, git, zsh, build tools), optional cleanup  
2. **Zsh for Root** — Oh My Zsh and plugins for root  
3. **Create Sudo User** — New user with sudo, optional Zsh/Oh My Zsh  
4. **Swap** — Add swapfile (size in GiB), optional swappiness  
5. **Firewall (UFW)** — Install/configure UFW (defaults, SSH, HTTP/HTTPS, enable)  
6. **Fail2Ban** — Install Fail2Ban for SSH protection, optional enable/start  
7. **SSH Keys & Hardening** — Add your pubkey, optional key for new user, optional hardening (PermitRootLogin no, password auth off)

### Usage

```bash
sudo ./bootstrap-server.sh
```

Or from repo root:

```bash
sudo ./server/bootstrap-server.sh
```

### Test with Docker

From project root:

```bash
./tests/run.sh ubuntu24 server/bootstrap-server.sh
```

### Notes

- Each step asks for confirmation; you can skip any step.  
- In containers or restricted environments, swap/UFW/SSH may be limited; the script skips or warns where needed.  
- After SSH hardening, test login in a **new** terminal before closing the current one.

---

## Outline Server VPN (`outline/`)

Install, configure and run **Outline Server VPN** (Shadowbox) on **Ubuntu or Debian** (latest LTS/stable) using **Docker Compose**.

**Script:** `outline/install-outline-server.sh`

- **Requires** Docker and Docker Compose (v2 plugin) to be installed already  
- Creates config and TLS cert under `/opt/outline` (or `--install-dir`)  
- Generates `compose.yml` and runs Shadowbox  
- Prints `apiUrl` and `certSha256` for [Outline Manager](https://getoutline.org/get-started/#step-2)

### Usage

```bash
sudo ./server/outline/install-outline-server.sh
```

Options: `--hostname` (required), `--api-port`, `--keys-port`, `--install-dir`. See `--help` or [outline/README.md](outline/README.md) for details.
