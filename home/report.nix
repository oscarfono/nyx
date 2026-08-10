{ config, pkgs, lib, ... }:

# nyx-report: gather the context an upstream maintainer will ask for, put it
# in a markdown draft, and open it for review BEFORE anything is submitted.
#
# The review step is the point. Journals and configs contain SSIDs,
# hostnames, paths and occasionally tokens. Nothing here posts anything on
# its own; `gh issue create` is offered at the end and requires confirmation.

let
  repo = "${config.home.homeDirectory}/Projects/nyx";

  nyx-report = pkgs.writeShellScriptBin "nyx-report" ''
    set -eu

    PROJECT="''${1:-}"
    if [ -z "$PROJECT" ]; then
      cat >&2 <<USAGE
usage: nyx-report <project>

  hyprland   compositor, window rules, dispatchers
  waybar     bar modules and their handlers
  nixpkgs    a package that is broken, missing or misbuilt
  emacs      emacs, straight.el, eat
  other      generic system context

Gathers context, opens a draft for you to review and redact, then offers to
file it with gh. Nothing is sent until you say so.
USAGE
      exit 1
    fi

    OUT=$(mktemp -t nyx-report-XXXXXX.md)
    COMMIT=$(git -C ${repo} rev-parse --short HEAD 2>/dev/null || echo unknown)
    DIRTY=$(git -C ${repo} status --porcelain 2>/dev/null | head -1)

    {
      echo "## Summary"
      echo
      echo "<!-- One sentence: what you did, what happened, what you expected. -->"
      echo
      echo "## Steps to reproduce"
      echo
      echo "1. "
      echo "2. "
      echo
      echo "## System"
      echo
      echo '```'
      echo "nixos:    $(nixos-version 2>/dev/null || echo unknown)"
      echo "kernel:   $(uname -sr)"
      echo "config:   github.com/oscarfono/nyx @ $COMMIT''${DIRTY:+ (dirty)}"
      echo '```'
      echo
    } > "$OUT"

    case "$PROJECT" in
      hyprland)
        {
          echo "## Hyprland"
          echo
          echo '```'
          ${pkgs.hyprland}/bin/hyprctl version 2>/dev/null | head -5
          echo
          ${pkgs.hyprland}/bin/hyprctl systeminfo 2>/dev/null | head -30
          echo '```'
          echo
          echo "<details><summary>Relevant config</summary>"
          echo
          echo '```lua'
          echo "<!-- paste the relevant part of ~/.config/hypr/hyprland.lua -->"
          echo '```'
          echo "</details>"
        } >> "$OUT"
        REPO_URL="hyprwm/Hyprland"
        ;;
      waybar)
        {
          echo "## Waybar"
          echo
          echo '```'
          ${pkgs.waybar}/bin/waybar --version 2>&1 | head -2
          ${pkgs.hyprland}/bin/hyprctl version 2>/dev/null | head -2
          echo '```'
          echo
          echo "### Log"
          echo
          echo '```'
          journalctl --user -u waybar -n 40 --no-pager 2>/dev/null
          echo '```'
        } >> "$OUT"
        REPO_URL="Alexays/Waybar"
        ;;
      nixpkgs)
        {
          echo "## Nix"
          echo
          echo '```'
          nix-info -m 2>/dev/null || nix --version
          echo '```'
          echo
          echo "### Build output"
          echo
          echo '```'
          echo "<!-- paste the failing nixos-rebuild or nix build output -->"
          echo '```'
        } >> "$OUT"
        REPO_URL="NixOS/nixpkgs"
        ;;
      emacs)
        {
          echo "## Emacs"
          echo
          echo '```'
          emacs --version 2>/dev/null | head -2
          echo "TERM=$TERM"
          echo "straight: $(git -C "$HOME/.emacs.d/straight/repos/straight.el" rev-parse --short HEAD 2>/dev/null || echo n/a)"
          echo '```'
          echo
          echo "### Service log"
          echo
          echo '```'
          journalctl --user -u emacs -n 30 --no-pager 2>/dev/null
          echo '```'
        } >> "$OUT"
        REPO_URL=""
        ;;
      *)
        {
          echo "## Context"
          echo
          echo '```'
          systemctl --failed --no-pager 2>/dev/null | head -10
          systemctl --user --failed --no-pager 2>/dev/null | head -10
          echo '```'
        } >> "$OUT"
        REPO_URL=""
        ;;
    esac

    {
      echo
      echo "---"
      echo "<!-- REVIEW BEFORE SUBMITTING."
      echo "     Logs can contain SSIDs, hostnames, paths and tokens."
      echo "     Delete this comment when you are done. -->"
    } >> "$OUT"

    ''${EDITOR:-emacsclient -c -a emacs} "$OUT"

    echo
    echo "Draft: $OUT"
    if [ -n "''${REPO_URL:-}" ] && command -v gh >/dev/null; then
      printf 'File this against %s? [y/N] ' "$REPO_URL"
      read -r reply
      case "$reply" in
        y|Y)
          printf 'Title: '
          read -r title
          ${pkgs.gh}/bin/gh issue create --repo "$REPO_URL" \
            --title "$title" --body-file "$OUT"
          ;;
        *) echo "Not submitted. Draft kept at $OUT" ;;
      esac
    else
      echo "Submit it by hand; no repo mapped for this project."
    fi

    echo
    echo "If this becomes a workaround, add an entry to KNOWN-ISSUES.md so"
    echo "nyx-doctor can tell you when to retest it."
  '';
in
{
  home.packages = [ nyx-report ];
}
