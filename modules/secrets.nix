{ config, pkgs, lib, username, ... }:

# Secrets, via sops-nix.
#
# Encrypted values live in secrets/secrets.yaml, committed to the repo.
# Decryption happens at activation time into /run/secrets, which is tmpfs
# and root-owned, so nothing plaintext ever reaches the Nix store (where it
# would be world-readable and permanent).
#
# The decryption key is the host's own SSH key, converted to age. That means
# a fresh machine can decrypt as soon as it has its host key, with nothing
# for you to carry around. It also means a machine that has not been given
# access cannot read them, which is the point.
#
# SAFETY: everything here is gated on secrets/secrets.yaml actually existing.
# Before you have created it the whole module is inert, so the config still
# evaluates and you cannot lock yourself out by rebuilding half-way through
# the setup.

let
  secretsFile = ../secrets/secrets.yaml;
  haveSecrets = builtins.pathExists secretsFile;
in
{
  config = lib.mkIf haveSecrets {
    sops = {
      defaultSopsFile = secretsFile;
      validateSopsFiles = false;

      age = {
        # Derived from /etc/ssh/ssh_host_ed25519_key at activation.
        sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        generateKey = false;
      };

      secrets = {
        # neededForUsers means this is decrypted early enough for user
        # creation, before the normal secrets pass.
        "${username}-password" = {
          neededForUsers = true;
        };
      };
    };

    # The account password now comes from the encrypted file rather than
    # from whatever you last typed into passwd.
    users.users.${username}.hashedPasswordFile =
      config.sops.secrets."${username}-password".path;

    # Root gets the same treatment, so rescue and emergency modes work.
    # This is the thing whose absence cost a reinstall.
    users.users.root.hashedPasswordFile =
      config.sops.secrets."${username}-password".path;

    # STILL TRUE, deliberately. Flip to false only after you have rebooted,
    # confirmed you can log in as ${username} AND as root at a TTY, and
    # confirmed `sudo` works. Once false, passwd stops working and the
    # encrypted file is the only way in.
    users.mutableUsers = lib.mkDefault true;
  };
}
