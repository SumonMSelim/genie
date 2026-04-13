# Git Scripts

## `setup-git-profile.sh`

Interactive setup for a named **git identity** — SSH key, GPG signing, per-directory gitconfig, and a `gclone` helper. Works with any git provider.

**Supported:** macOS · Ubuntu/Debian Linux  
**Providers:** GitHub · GitLab · Bitbucket · Gitea · Azure DevOps · Custom

### What It Does (in order)

1. **Profile Information** — Name slug, display name, email, username, work directory, provider, SSH port
2. **Work Directory** — Creates the directory if it doesn't exist
3. **SSH Key** — Generates an ED25519 key (`~/.ssh/id_ed25519_<profile>`), optional passphrase + keychain (macOS)
4. **SSH Config** — Adds a named `Host` entry to `~/.ssh/config` with `IdentitiesOnly yes`
5. **GPG Key** — Generate new or use existing; configures commit + tag signing (skipped for Bitbucket/Azure)
6. **Per-profile Gitconfig** — Writes `~/.gitconfig-<profile>` with name, email, and optional GPG key
7. **Global Gitconfig** — Adds `includeIf "gitdir:..."` to activate the profile inside the work directory, plus a `url.insteadOf` clone shorthand
8. **Profile Map + gclone** — Registers the profile in `~/.config/git-profiles` and writes the `gclone` shell helper (once, shared across profiles)
9. **Test SSH** — Optional live connection test to the provider
10. **Summary** — Prints the SSH/GPG public keys to add to your provider, and usage examples

### Usage

```bash
./setup-git-profile.sh
```

Or from repo root:

```bash
./git/setup-git-profile.sh
```

Run once per profile. The script is **idempotent** — safe to re-run.

### After Setup

**1. Add your SSH public key** to the provider (the script prints it at the end):

| Provider | URL |
|---|---|
| GitHub | https://github.com/settings/ssh/new |
| GitLab | https://gitlab.com/-/profile/keys |
| Bitbucket | https://bitbucket.org/account/settings/ssh-keys/ |
| Azure DevOps | https://dev.azure.com/{org}/_usersSettings/keys |

**2. Add your GPG public key** (if generated) to the provider — also printed at the end.

**3. Enable `gclone`** — add to `~/.zshrc` or `~/.bashrc`:

```bash
source ~/.config/genie/gclone.sh
```

**4. Clone repositories** — two ways:

```bash
# url.insteadOf shorthand (works from anywhere)
git clone personal:user/repo

# gclone — auto-detects profile from current directory
cd ~/Personal && gclone user/repo

# gclone — explicit profile, works from anywhere
gclone -p personal user/repo
```

**5. Add remote origin** to a new local repo:

```bash
# Using url.insteadOf shorthand
git remote add origin personal:user/repo.git

# Or with the explicit SSH alias
git remote add origin git@github.com-personal:user/repo.git

# Then push the first commit
git push -u origin main
```

**6. Verify identity** inside any repo in your work directory:

```bash
git config user.email
git config user.name
```

### Test with Docker

From project root:

```bash
./tests/run.sh ubuntu24 git/setup-git-profile.sh
```

### Notes

- Each step confirms before making changes; you can skip any step.
- Multiple profiles are supported — run the script once per identity (e.g. `personal`, `work`).
- The `gclone` helper is written once and shared across all profiles.
- GPG signing is skipped automatically for providers that don't support it (Bitbucket, Azure DevOps).
