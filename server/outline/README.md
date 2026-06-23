# Outline Server VPN

Script to **install**, **configure**, and **run** [Outline Server](https://getoutline.org/) (Shadowbox) on **Ubuntu** or **Debian** using **Docker Compose**.

## Requirements

- **Docker** and **Docker Compose** (v2 plugin) installed and working  
- **Ubuntu** 20.04 LTS (Focal), 22.04 LTS (Jammy), 24.04 LTS (Noble), or newer — or **Debian** 11 (Bullseye), 12 (Bookworm), 13 (Trixie), or newer  
- Root or `sudo`  
- **`--hostname`** (public hostname or IP for the server) — required

## What it does

1. **Configure** — Creates an install directory (default `/opt/outline`), generates a Management API secret, a self-signed TLS certificate, and server config.
2. **Run** — Generates a `compose.yml` and runs `docker compose up -d` for Shadowbox.

After startup, the script creates a first access key and prints the **apiUrl** and **certSha256** so you can add the server in [Outline Manager](https://getoutline.org/get-started/#step-2).

## Usage

```bash
sudo ./server/outline/install-outline-server.sh
```

Or from the `server/outline` directory:

```bash
sudo ./install-outline-server.sh
```

### Options

| Option | Description |
|--------|-------------|
| `--hostname HOST` | Public hostname or IP **(required)** |
| `--api-port PORT` | Management API port (default: random) |
| `--keys-port PORT` | Port for new access keys (default: server-assigned) |
| `--install-dir DIR` | State directory (default: `/opt/outline`) |
| `-h`, `--help` | Show help |

### Examples

```bash
# Required: pass your server's public hostname or IP
sudo ./install-outline-server.sh --hostname vpn.example.com --api-port 8081

# Custom install directory
sudo ./install-outline-server.sh --hostname vpn.example.com --install-dir /srv/outline
```

## After install

1. **Add server in Outline Manager**  
   Use the printed JSON (`apiUrl` + `certSha256`) or the contents of `/opt/outline/access.txt`.

2. **Open firewall ports**  
   Allow the Management API port (TCP) and the access-key port (TCP and UDP). The script prints a reminder and example UFW commands.

3. **Manage the stack**  
   - Stop: `docker compose -f /opt/outline/compose.yml --project-directory /opt/outline down`  
   - Logs: `docker compose -f /opt/outline/compose.yml --project-directory /opt/outline logs -f`

## Files created

Under the install directory (e.g. `/opt/outline`):

- `compose.yml` — Generated Compose file for Shadowbox.
- `persisted-state/` — Certificates, server config, and state (do not remove).
- `access.txt` — Lines `apiUrl:...` and `certSha256:...` for Outline Manager.

## Notes

- The script uses the official image `quay.io/outline/shadowbox:stable` and `network_mode: host`, so port conflicts with other services are possible; use `--api-port` and `--keys-port` if needed.
