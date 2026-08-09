{ config, pkgs, lib, ... }:

# GPG and SSH agents, both as user services so they start with the session
# and stop with it.
#
# Deliberately SEPARATE agents. gpg-agent can serve SSH keys via
# enableSshSupport, but that path expects your SSH identity to be a GPG
# authentication subkey. Yours is a standalone ed25519 file, so pointing
# gpg-agent at it means maintaining ~/.gnupg/sshcontrol by hand for no gain.
# One agent per job is simpler and easier to reason about.

{
  # -------------------------------------------------------------------
  # GPG
  # -------------------------------------------------------------------
  services.gpg-agent = {
    enable = true;
    enableSshSupport = false;   # see the note above

    # pinentry-gnome3, NOT curses: the Emacs daemon and any GUI app have no
    # terminal for a curses prompt to draw in, so the passphrase request
    # hangs forever and looks like a hung application.
    pinentry.package = pkgs.pinentry-gnome3;

    # Unlock once per session rather than per operation. Long enough to stop
    # being irritating during a work session, short enough that a locked
    # screen overnight means re-entering it.
    defaultCacheTtl = 3600;
    maxCacheTtl = 28800;

    # Same for signing, which is what git commits hit.
    defaultCacheTtlSsh = 3600;
    maxCacheTtlSsh = 28800;

    extraConfig = ''
      allow-loopback-pinentry
    '';
  };

  programs.gpg = {
    enable = true;
    settings = {
      # Prefer strong digests, and do not leak your key ID to whoever
      # receives an encrypted file.
      personal-digest-preferences = "SHA512 SHA384 SHA256";
      cert-digest-algo = "SHA512";
      throw-keyids = false;
      keyid-format = "0xlong";
      with-fingerprint = true;
    };
  };

  # -------------------------------------------------------------------
  # SSH
  # -------------------------------------------------------------------
  services.ssh-agent.enable = true;

  programs.ssh = {
    enable = true;

    # home-manager is removing its implicit defaults, so opt out and state
    # what we actually want. matchBlocks became `settings` in the same
    # change.
    enableDefaultConfig = false;

    settings = {
      "github.com" = {
        user = "git";
        identityFile = "~/.ssh/id_ed25519_github";
        identitiesOnly = true;
        addKeysToAgent = "yes";
      };

      "*" = {
        # Keys join the agent on first use rather than at login, so nothing
        # prompts for a key you may not touch today.
        addKeysToAgent = "yes";
        serverAliveInterval = 60;
        # Do not hand your agent to a remote host unless you mean to.
        forwardAgent = false;
        hashKnownHosts = true;
        controlMaster = "no";
        compression = false;
      };
    };
  };
}
