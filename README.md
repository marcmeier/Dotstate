# Dotstate

Dotfiles management tooling for [Omarchy](https://omarchy.org/) (Arch +
Hyprland), plus an Omarchy bar-widget plugin that shows your sync status
and gives you one-click sync/drift/link-check actions.

Dotstate itself ships **no personal configuration** — it's a template repo
for the tooling only. You bring your own `home/` and `packages/*.txt`.

## What you get

- `install.sh` — symlinks your configs into `$HOME`, installs your tracked
  pacman/AUR packages, sets up the secret-scan git hook and the auto-sync
  timer. Idempotent, safe to re-run.
- `adopt.sh` — turns an existing real config file into a repo-tracked
  symlink (`--host` for machine-specific files).
- `check-adoptable.sh` — read-only: scans `$HOME` for config-looking paths
  not yet tracked and prints ready-to-run `adopt.sh` commands, so you don't
  have to hunt for them yourself on a new machine.
- `backup.sh` — auto-commits and pushes changes; run by a systemd user
  timer daily and ~5 minutes after login. Writes the status the bar widget
  reads.
- `check-drift.sh` — read-only: `packages/*.txt` vs. what's actually
  installed.
- `check-links.sh` — read-only: are all tracked configs still correctly
  symlinked?
- `clean-backups.sh` — cleans up `~/.dotstate-backup-*` dirs left behind by
  `install.sh`/`adopt.sh` once they're redundant.
- `githooks/pre-commit` — blocks a commit if `gitleaks` finds a likely
  secret in the staged changes.
- `manifest.json` + `Panel.qml` + `Model.js` — an Omarchy Quickshell
  bar-widget plugin (see below). These live at the repo root, not in a
  subfolder, because `omarchy-plugin-validate` requires `manifest.json`
  directly at the root of whatever `omarchy plugin add` clones.

## Quickstart

1. Click **"Use this template"** on this repo to create your own (can be
   private) dotfiles repo.
2. Clone it, e.g. to `~/Projects/dotfiles`.
3. Run `./check-adoptable.sh` to find config-looking paths already on this
   machine that aren't tracked yet, and `./adopt.sh` the ones you want (see
   its printed suggestions) — or add files under `home/` (mirrors `$HOME`)
   by hand. Add your extra packages in `packages/pacman.common.txt` /
   `packages/aur.common.txt`.
4. `./install.sh`

```bash
git clone git@github.com:<you>/<your-dotfiles-repo>.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh
```

## Host-specific configs

Not every config should be identical on every machine (monitor layout,
CPU-specific packages, ...). Alongside `home/` (shared) you can add an
optional `home.<hostname>/` (hostname via the `hostname` command), which
`install.sh` links on top — it wins on overlap. Same idea for packages via
`packages/pacman.<hostname>.txt` / `packages/aur.<hostname>.txt`.

```bash
./adopt.sh --host ~/.config/hypr/monitors.lua
```

`home.<hostname>/` is purely additive — a new/renamed machine without an
overlay just gets `home/`, nothing breaks.

## Secret scan

`install.sh` points this repo's git hooks at `githooks/`. The `pre-commit`
hook runs `gitleaks` over staged changes and blocks the commit on a likely
secret (also applies to `backup.sh`'s automatic commits). Requires
`gitleaks` (tracked in `packages/pacman.common.txt`); if it's not
installed, the scan is skipped rather than blocking you. Bypass a
confirmed false positive once with `git commit --no-verify`.

## Automatic sync

`backup.sh` commits and pushes any changes (with a `git pull --rebase`
first, so multiple machines don't fight each other), run by the
`dotstate-backup.timer` systemd user timer that `install.sh` installs:
daily, plus ~5 minutes after login, catching up on missed runs if the
machine was off. Trigger it manually with:

```bash
systemctl --user start dotstate-backup.service
journalctl --user -u dotstate-backup.service   # logs
```

A failed run sends a desktop notification and leaves a status file at
`~/.cache/dotstate/status.json`, which the bar widget below reads.

## The bar widget

`manifest.json`/`Panel.qml`/`Model.js` at the repo root form an Omarchy
shell plugin (see the [Omarchy shell
docs](https://github.com/basecamp/omarchy/blob/quattro/shell/README.md)
for how plugins work in general). It shows an icon in your bar:

| Color | Meaning |
|---|---|
| Dim | Not configured yet, or no sync has run |
| Normal (foreground) | Last sync succeeded |
| Urgent | Last sync failed |

Clicking it opens a small panel with a **dotfiles repo path** field (see
below), **Sync now**, **Check package drift**, **Check symlinks**, and
**Open repo**.

Add it once you've created your own repo from this template:

```bash
omarchy plugin add https://github.com/<you>/<your-dotfiles-repo>.git --enable --yes
```

**Important:** this clones the plugin into its own directory under
`~/.config/omarchy/plugins/`, separate from your actual working checkout
(e.g. `~/Projects/dotfiles`). Because of that, the widget doesn't guess
where your real repo is: click the icon, type the path you cloned it to in
step 2 of the Quickstart into the **"Dotfiles repo path"** field, and hit
**Save** (or Enter). This writes it inline into your widget's entry in
`~/.config/omarchy/shell.json` — there's no separate settings page for
third-party widgets in Setup > Plugins as of this Omarchy version.

## CI

Every push runs `shellcheck` over all scripts and `gitleaks` over the full
git history (`.github/workflows/ci.yml`).

## License

MIT — see [LICENSE](LICENSE).
