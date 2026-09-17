#!/usr/bin/env bash
# Adopt existing config files/directories on this system into the repo.
#
# Usage: ./adopt.sh [--host] <path> [<path> ...]
#
# This is the reverse of install.sh: instead of linking repo files into
# $HOME, it takes real files that already live under $HOME, moves them
# into home/<relative-path>, replaces the original with a symlink into
# the repo (same layout install.sh creates), and stages them in git.
#
# --host adopts into home.<hostname>/ instead of home/, for config that
# is specific to this machine (different hardware, monitors, etc.) and
# should not be shared with other machines.
#
# Safe to re-run: paths already adopted (already a symlink into the repo)
# are skipped.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_NAME="home"

log()  { echo -e "\033[1;34m==>\033[0m $*"; }
err()  { echo -e "\033[1;31m==>\033[0m $*" >&2; }

adopt_path() {
  local target="$1"
  # Normalize to an absolute path WITHOUT resolving symlinks: if $target
  # is itself a symlink (e.g. already adopted, pointing into the repo),
  # we need to operate on the symlink, not on whatever it points to.
  target="$(realpath -sm "$target")"

  case "$target" in
    "$HOME"/*) ;;
    *) err "Skipping $target: not under \$HOME"; return 1 ;;
  esac

  local rel="${target#"$HOME"/}"
  local dest="$REPO_DIR/$DEST_NAME/$rel"

  if [ -L "$target" ]; then
    local current_link
    current_link="$(readlink -f "$target" 2>/dev/null || true)"
    if [ "$current_link" = "$(readlink -f "$dest" 2>/dev/null || true)" ]; then
      log "Already adopted: $rel"
      return 0
    fi
    case "$current_link" in
      "$REPO_DIR"/*)
        err "Skipping $rel: already adopted elsewhere in the repo ($current_link) - use 'git mv' manually to relocate"
        return 1
        ;;
    esac
  fi

  if [ ! -e "$target" ]; then
    err "Skipping $rel: does not exist"
    return 1
  fi

  if [ -e "$dest" ]; then
    err "Skipping $rel: $DEST_NAME/$rel already exists in repo (resolve manually)"
    return 1
  fi

  mkdir -p "$(dirname "$dest")"
  cp -a "$target" "$dest"
  rm -rf "$target"
  ln -s "$dest" "$target"
  git -C "$REPO_DIR" add -- "$DEST_NAME/$rel"
  log "Adopted $rel -> $DEST_NAME/$rel"
}

main() {
  while [ "$#" -gt 0 ] && [ "$1" = "--host" ]; do
    DEST_NAME="home.$(hostname)"
    shift
  done

  if [ "$#" -eq 0 ]; then
    err "Usage: $0 [--host] <path> [<path> ...]"
    exit 1
  fi

  local status=0
  for p in "$@"; do
    adopt_path "$p" || status=1
  done

  log "Done. Review with:  git -C \"$REPO_DIR\" status"
  log "Then commit + push when ready."
  exit "$status"
}

main "$@"
