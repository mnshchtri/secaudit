# secaudit

A read-only security audit for Arch Linux desktops, built for [Omarchy](https://omarchy.org)
but useful on any Arch install. It checks the machine, scores it, explains each finding and
offers a fix command where one is safe to suggest.

It comes in three parts:

| Command        | What it is                                                                     |
| -------------- | ------------------------------------------------------------------------------ |
| `secaudit`     | The audit engine. A single Bash script; plain-text, report and JSON output.    |
| `secaudit-tui` | Terminal app (Python [Textual](https://textual.textualize.io)) for the engine. |
| `secaudit-ui`  | Older, lighter front-end built with [gum](https://github.com/charmbracelet/gum). |

## What it checks

- **Packages:** pending updates, known CVEs (with `arch-audit`), kernel reboot needed, AUR packages, pacman signature level, pacman hooks that pipe downloads into a root shell
- **Boot and disk:** LUKS version and PBKDF, Secure Boot, bootloader config permissions, swap
- **Kernel hardening:** about 20 sysctl settings, kernel taint, active LSMs, `/etc/ld.so.preload`
- **Firewall and network:** ufw state and rules, ufw-docker, services listening on external interfaces, DNS-over-TLS, LLMNR, saved open Wi-Fi networks
- **SSH:** sshd state and effective config, `~/.ssh` permissions, keys without a passphrase
- **Users:** extra UID 0 accounts, empty passwords, NOPASSWD sudo, root-equivalent groups, autologin, idle lock
- **Filesystem:** world-writable files, SUID/SGID binaries not owned by a package, writable `PATH` entries
- **Persistence:** failed units, local and user systemd units, autostart entries, cron, remote-exec lines in shell rc files
- **Containers:** privileged containers, host networking, mounted Docker socket, ports published on all interfaces
- **Secrets:** credential file permissions, token-like lines in shell history, readable `.env` and key files (values are never printed)
- **Rootkit indicators:** modules or processes hidden from the usual tools, binaries running from deleted files, executables in temp dirs

The engine never changes the system. Fix commands are only run from the TUI after you confirm them.

## Install

```bash
git clone https://github.com/<you>/secaudit.git
cd secaudit
./install.sh              # symlinks bin/* into ~/.local/bin and adds a launcher entry
./install.sh --sysctl     # optional: install the kernel hardening drop-in (needs sudo)
./install.sh --uninstall  # remove the symlinks and launcher entry
```

Because the commands are symlinks, edits in the repo are live immediately.

**Requirements:** `bash`, `jq`, `iproute2` (`ss`), `pacman`. `secaudit-tui` needs
[`uv`](https://docs.astral.sh/uv/), which downloads and caches Textual on first run; nothing is
installed system-wide. `secaudit-ui` needs `gum`. Optional extras: `arch-audit`, `rkhunter`, `lynis`.

## Usage

```bash
secaudit-tui                  # interactive app
secaudit-tui --scan full      # start a scan right away

secaudit                      # quick pass as your user
sudo secaudit                 # full coverage (shadow, sudoers, firewall rules, LUKS headers)
sudo secaudit --deep          # + package file checksums and a whole-disk SUID scan (slow)
sudo secaudit --user alice    # audit alice's home folder (default: whoever ran sudo)
secaudit --report audit.txt   # also write a plain-text copy
secaudit --json findings.jsonl  # one JSON object per finding
```

`secaudit` exits with 1 if any check fails, so it can be used in scripts.

### TUI keys

| Key     | Action                                           |
| ------- | ------------------------------------------------ |
| `s`     | Start a scan (full, quick or deep)               |
| `r`     | Rescan with the same mode                        |
| `space` | Select a finding for batch fixing                |
| `*`     | Select every fixable finding in the view         |
| `x`     | Run the fix for the selection or current finding |
| `a`     | Accept the risk (stops counting against score)   |
| `i`     | Explain the finding with AI (Claude)             |
| `I`     | AI action plan for the whole scan                |
| `c`     | Copy the fix command or advice                   |
| `/`     | Search findings                                  |
| `1`–`5` | Issues / Accepted / Notes / Passed / All tabs    |
| `h`     | Scan history, trend and changes                  |
| `o`     | Full text output of the scan                     |
| `e`     | Export a Markdown checklist                      |
| `?`     | All keys                                         |

## AI explanations

Press `i` on a finding and Claude explains it in plain terms: what it means, why it matters on a
personal workstation, how to fix it step by step, trade-offs, and how to verify. Ask follow-up
questions in the box at the bottom. `I` produces a prioritized action plan for every open issue.

- **Opt-in.** Nothing is sent until you press `i` or `I` and agree once.
- **What's sent:** the finding's section, message, details and suggested fix. Your username,
  hostname and home path are replaced with `<user>`, `<host>` and `~` first. The scan never
  collects secret values.
- **Claude Code (default when installed):** uses your existing Claude Code sign-in, so no API key
  is needed and usage counts toward your Claude plan. It runs `claude -p` with every tool, MCP
  server, slash command and hook turned off, so it can only answer. Follow-up questions continue
  the same Claude Code session. If `claude` isn't on the launcher's `PATH`, set
  `SECAUDIT_CLAUDE_BIN`.
- **API key (alternative):** choose "Use an API key instead" in the setup dialog. Uses
  `ANTHROPIC_API_KEY` (or an `ant auth login` profile), or a key pasted in the app, stored in
  `~/.config/secaudit/anthropic-api-key` with mode 600. API usage is billed to your Anthropic
  account; if the model declines a request, the API retries it on Anthropic's recommended
  fallback model.
- **Model:** Claude Code's default model, or `claude-opus-5-5` with an API key, at `medium` effort.
  Override with `SECAUDIT_AI_MODEL` and `SECAUDIT_AI_EFFORT`. To switch backends later, edit
  `ai_backend` (`claude-code` or `api`) in `~/.config/secaudit/config.json`.
- **Saved answers:** first explanations are saved under `~/.local/state/secaudit/ai-cache`, so
  reopening a finding costs nothing; `ctrl+r` asks again.
- AI-suggested commands can be copied but are never run by the app. Only secaudit's own fixes have
  a Run button.

## Scoring

`100 − 10 × fail − 2 × warn`, floored at 0. Grades: A ≥ 90, B ≥ 80, C ≥ 70, D ≥ 60, F below.
Accepted risks don't count.

## Data

Everything lives under `${XDG_STATE_HOME:-~/.local/state}/secaudit`:

- `runs/<timestamp>/`: `findings.jsonl`, `output.txt`, `meta.json`, `applied` (one folder per scan, newest 30 kept)
- `accepted.json`: accepted risks, matched by section and message with numbers masked
- `ai-cache/`: saved AI explanations

## JSON format

`secaudit --json FILE` writes one object per line:

```json
{"sev": "warn", "section": "SSH", "msg": "~/.ssh/id_ed25519 has no passphrase",
 "detail": "", "fix": "ssh-keygen -p -f ~/.ssh/id_ed25519", "hint": ""}
```

`sev` is one of `fail`, `warn`, `pass`, `info`, `skip`. `fix` is a shell command; `hint` is prose
advice for findings that can't be fixed automatically.

## Adding a check

Checks live in `bin/secaudit`, grouped under `section "Name"` headers. Use the helpers:

```bash
ok   "message"       # pass
wn   "message"       # warning (−2)
bad  "message"       # failure (−10)
info "message"       # context, not scored
skp  "message"       # skipped
detail <<<"$lines"   # attach details to the last finding
fix  "command"       # attach a fix command (shown in the TUI)
hint "advice"        # attach advice when no safe automatic fix exists
need_root "what"     # skip with a note unless running as root
```

A new `section` shows up in the TUI's sidebar and scan progress automatically.
