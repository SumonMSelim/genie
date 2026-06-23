# 🧞‍♂️ Genie

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![Scripts](https://img.shields.io/badge/scripts-3-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

*Your magical development assistant - granting dev wishes, one script at a time*

A collection of handy scripts and utilities to streamline development workflow and system setup.

## What's Inside

Genie is your personal collection of utility scripts and tools that make developers' lives easier. 
Whether you're setting up a new machine or automating repetitive tasks, Genie has you covered.

## Available Scripts

| Category | Script                      | Description                                                                                               | Guide                            |
|----------|-----------------------------|-----------------------------------------------------------------------------------------------------------|----------------------------------|
| Terminal | `mac-terminal-installer.sh` | Complete macOS iterm2 terminal setup with Zsh, Oh My Zsh, Powerlevel10k, Nerd Fonts, and modern CLI tools | [View Guide](terminal/README.md) |
| Server   | `bootstrap-server.sh`       | Debian/Ubuntu server bootstrap: packages, Zsh, sudo user, swap, UFW, Fail2Ban, SSH keys & hardening       | [View Guide](server/README.md)   |
| Server   | `install-outline-server.sh` | Install and run Outline Server VPN (Shadowbox) on Ubuntu/Debian via Docker Compose                        | [View Guide](server/outline/README.md) |
| Git      | `setup-git-profile.sh`      | Set up a named git identity: SSH key, GPG signing, per-directory gitconfig, and gclone helper             | [View Guide](git/README.md)      |

---

*More scripts coming soon! Stay tuned.*

## Getting Started

1. Clone this repository:
   ```bash
   git clone https://github.com/SumonMSelim/genie.git
   cd genie
   ```

2. Navigate to the folder of the script(s):
   ```bash
   cd terminal  # or server, etc.
   ```

3. Follow the guide in that folder's README!

## Testing a Script (using Docker)

Use the test script to run/test a script inside a Docker container.

**Requirements:** Docker + Docker Compose

```bash
./tests/run.sh ubuntu24 server/bootstrap-server.sh
```

For scripts that require Docker inside the container (e.g. Outline Server), use the dedicated test script:

```bash
./tests/run.sh ubuntu24 tests/test-outline-server.sh
```

Notes:
- `script_path` is **relative to the project root** (example: `server/bootstrap-server.sh`)
- You’ll be prompted before the environment is stopped (so you can keep it running for debugging)
- Test containers run with `privileged: true` to support Docker-in-Docker

## Philosophy

Genie follows these principles:
- **Magic, not mystery** - Scripts are well-documented and easy to understand
- **Wish granting** - Automate the boring stuff so you can focus on creating
- **Safe sorcery** - Always review before running, with clear explanations
- **Growing grimoire** - Continuously adding new spells (scripts) to the collection

## Contributing

Have a useful script or utility? Contributions are welcome! Please feel free to submit a Pull Request.

**Guidelines:**
- Place scripts in appropriate category folders
- Include a detailed README.md in the category folder
- Follow existing naming conventions
- Test your scripts before submitting

## Disclaimer

Always review scripts before running them on your system. While these scripts are tested, use them at your own risk.

## License

[MIT License](LICENSE) - feel free to use and modify as needed.

---

**Tip:** Star this repo if Genie granted your wishes!
