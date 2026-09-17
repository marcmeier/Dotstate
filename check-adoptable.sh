#!/usr/bin/env bash
# Read-only: finds top-level paths under $HOME that look like configs but
# aren't tracked in this repo yet, and prints ready-to-run adopt.sh commands.
#
# Usage: ./check-adoptable.sh
#
# This is a starting point for onboarding a new machine (or this repo
# itself), not a verdict: it deliberately excludes known noise (browser
# profiles, caches, app sync state - see DENYLIST below) so it doesn't
# suggest scooping up secrets or gigabytes of cache into git, but you're
# still the one deciding what actually belongs in the repo. Review the
# list before running any of the printed commands. Checks top-level
# entries only (e.g. all of ~/.config/nvim as one candidate), matching
# the granularity adopt.sh itself adopts at.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\033[1;34m==>\033[0m $*"; }

# Extend this rather than fighting it - a false positive here is just a
# suggestion you ignore, not a wrong adopt (adopt.sh itself never runs
# automatically off this list).
DENYLIST=(
  ".cache" ".local" ".dotstate-backup-*" ".dotfiles-backup-*"
  "google-chrome" "google-chrome-beta" "chromium" "BraveSoftware"
  "microsoft-edge" "vivaldi" "Slack" "discord" "Signal" "obsidian"
  "mozilla" "thunderbird" "evolution" "spotify"
  "Nextcloud" "nextcloud" "syncthing" "dropbox" ".dropbox"
  "pulse" "dconf" "ibus"
  # Credential material, not config - never suggest these, unlike
  # ~/.config/git/config which is a legitimate, secret-free config to adopt.
  "gnupg" "ssh" "password-store"
)

is_denied() {
  local name="$1" pattern
  for pattern in "${DENYLIST[@]}"; do
    # shellcheck disable=SC2053 # intentional glob match against $pattern
    [[ "$name" == $pattern ]] && return 0
  done
  return 1
}

already_tracked() {
  local target="$1"
  if [ -L "$target" ]; then
    case "$(readlink -f "$target" 2>/dev/null)" in
      "$REPO_DIR"/*) return 0 ;;
    esac
  fi
  return 1
}

# Prints the real path of the first symlink at or under $1 that resolves
# outside this repo, or nothing if there is none. install.sh symlinks
# individual files, not whole directories, so a directory that looks
# untouched at the top (not a symlink itself) can still be full of files
# another dotfiles repo already manages - suggesting it whole would have
# adopt.sh copy those symlinks-as-symlinks instead of their real content
# and then delete the originals, breaking whatever pointed at them.
find_foreign_symlink() {
  local path="$1" link real
  if [ -L "$path" ]; then
    real="$(readlink -f "$path" 2>/dev/null || true)"
    case "$real" in
      "$REPO_DIR"/*) ;;
      *) [ -n "$real" ] && { echo "$real"; return 0; } ;;
    esac
    return 1
  fi
  [ -d "$path" ] || return 1
  while IFS= read -r -d '' link; do
    real="$(readlink -f "$link" 2>/dev/null || true)"
    case "$real" in
      "$REPO_DIR"/*) ;;
      *) [ -n "$real" ] && { echo "$real"; return 0; } ;;
    esac
  done < <(find "$path" -type l -print0 2>/dev/null)
  return 1
}

main() {
  local candidates=() managed_elsewhere=() entry base foreign

  for entry in "$HOME"/.config/*; do
    [ -e "$entry" ] || continue
    base="$(basename "$entry")"
    is_denied "$base" && continue
    already_tracked "$entry" && continue
    foreign="$(find_foreign_symlink "$entry")" || true
    if [ -n "$foreign" ]; then
      managed_elsewhere+=(".config/$base -> $foreign")
      continue
    fi
    candidates+=(".config/$base")
  done

  shopt -s dotglob nullglob
  for entry in "$HOME"/.*; do
    base="$(basename "$entry")"
    case "$base" in
      . | .. | .config) continue ;;
    esac
    [ -f "$entry" ] || continue
    is_denied "$base" && continue
    already_tracked "$entry" && continue
    foreign="$(find_foreign_symlink "$entry")" || true
    if [ -n "$foreign" ]; then
      managed_elsewhere+=("$base -> $foreign")
      continue
    fi
    candidates+=("$base")
  done
  shopt -u dotglob nullglob

  if [ "${#managed_elsewhere[@]}" -gt 0 ]; then
    log "Already managed by another repo (not suggesting these):"
    printf '    %s\n' "${managed_elsewhere[@]}"
    echo
  fi

  if [ "${#candidates[@]}" -eq 0 ]; then
    log "Nothing else obviously untracked found under \$HOME."
    log "Nothing was changed."
    exit 0
  fi

  log "Untracked config-looking paths under \$HOME (review before adopting):"
  printf '    %s\n' "${candidates[@]}"

  echo
  log "Nothing was changed. Adopt what you actually want, e.g. all at once:"
  local quoted=()
  local c
  for c in "${candidates[@]}"; do
    quoted+=("\"\$HOME/$c\"")
  done
  echo "    ./adopt.sh ${quoted[*]}"
  log "...or pick individually, and use --host for anything machine-specific."
}

main "$@"
