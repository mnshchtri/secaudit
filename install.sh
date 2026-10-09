#!/bin/bash
# Install secaudit for the current user by symlinking bin/ into ~/.local/bin,
# so edits in this repo take effect immediately.
#
# Usage: ./install.sh              install commands and the launcher entry
#        ./install.sh --sysctl     also install the kernel hardening drop-in (sudo)
#        ./install.sh --uninstall  remove symlinks and the launcher entry

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BINDIR=${BINDIR:-$HOME/.local/bin}
APPDIR=${XDG_DATA_HOME:-$HOME/.local/share}/applications
DESKTOP=$APPDIR/secaudit.desktop
SYSCTL_DEST=/etc/sysctl.d/99-zz-hardening.conf
COMMANDS=(secaudit secaudit-tui secaudit-ui)

say() { printf '  %s\n' "$*"; }

link() { # src dest
  local src=$1 dest=$2
  if [[ -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
    say "ok      ${dest/#$HOME/~}"
    return
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -f "$dest" && ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
      rm -f "$dest" # identical copy from a manual install
    else
      mv "$dest" "$dest.bak.$(date +%s)"
      say "backup  ${dest/#$HOME/~} (it differed from the repo)"
    fi
  fi
  ln -s "$src" "$dest"
  say "linked  ${dest/#$HOME/~} -> ${src/#$HOME/~}"
}

install_desktop() {
  local launch terminal=false
  # Omarchy: open in a regular terminal window through uwsm; elsewhere let the DE pick a terminal
  if command -v uwsm-app >/dev/null && command -v xdg-terminal-exec >/dev/null; then
    launch='uwsm-app -- xdg-terminal-exec --app-id=org.secaudit.tui --title="Security Audit" -e'
  else
    launch='' terminal=true
  fi
  mkdir -p "$APPDIR"
  sed -e "s|@BINDIR@|$BINDIR|g" -e "s|@LAUNCH@ |${launch:+$launch }|" -e "s|@TERMINAL@|$terminal|" \
    "$REPO/share/secaudit.desktop.in" >"$DESKTOP"
  command -v update-desktop-database >/dev/null && update-desktop-database "$APPDIR" 2>/dev/null || true
  say "wrote   ${DESKTOP/#$HOME/~}"
}

check_deps() {
  local missing=()
  for dep in jq ss pacman; do command -v "$dep" >/dev/null || missing+=("$dep"); done
  command -v uv >/dev/null || missing+=("uv (for secaudit-tui)")
  command -v gum >/dev/null || missing+=("gum (only for secaudit-ui)")
  ((${#missing[@]})) && say "note    missing: ${missing[*]}"
  [[ ":$PATH:" == *":$BINDIR:"* ]] || say "note    $BINDIR is not on your PATH"
  return 0
}

case "${1:-}" in
  --uninstall)
    for c in "${COMMANDS[@]}"; do
      if [[ -L "$BINDIR/$c" && "$(readlink -f "$BINDIR/$c")" == "$REPO/bin/$c" ]]; then
        rm -f "$BINDIR/$c" && say "removed ${BINDIR/#$HOME/~}/$c"
      fi
    done
    rm -f "$DESKTOP" && say "removed ${DESKTOP/#$HOME/~}"
    [[ -f "$SYSCTL_DEST" ]] && say "kept    $SYSCTL_DEST (remove with: sudo rm $SYSCTL_DEST && sudo sysctl --system)"
    say "Scan history is kept in ${XDG_STATE_HOME:-$HOME/.local/state}/secaudit"
    exit 0
    ;;
  "" | --sysctl) ;;
  -h | --help) sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 0 ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac

echo "Installing secaudit from ${REPO/#$HOME/~}"
mkdir -p "$BINDIR"
chmod +x "$REPO"/bin/*
for c in "${COMMANDS[@]}"; do link "$REPO/bin/$c" "$BINDIR/$c"; done
install_desktop

if [[ "${1:-}" == --sysctl ]]; then
  sudo install -Dm644 "$REPO/extras/sysctl/99-zz-hardening.conf" "$SYSCTL_DEST"
  sudo sysctl --system >/dev/null
  say "applied $SYSCTL_DEST"
fi

check_deps
echo "Done. Run: secaudit-tui"
