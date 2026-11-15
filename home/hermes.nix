{ inputs, ... }:

# Hermes Agent, from Nous Research. https://github.com/NousResearch/hermes-agent
#
#   hermes setup         select the model provider and the messaging platforms
#   hermes               start a conversation in the terminal
#   hermes-desktop       the Electron application. The launcher also starts it.
#
# The state is in ~/.hermes: config.yaml, .env, auth.json, the memory and the
# sessions.
#
# The installation has two stages, because of managed mode.
# `services.hermes-agent.enable` sets HERMES_MANAGED. In managed mode the CLI
# refuses `hermes setup` and `hermes config set`, and it does not write
# config.yaml.
#
#   1. Now: the CLI and the desktop application, with no service. Run
#      `hermes setup` one time. Select the provider and Telegram there.
#   2. Then: set `services.hermes-agent` below, and set linger in
#      hosts/t490/default.nix. The module merges `settings` into the
#      config.yaml on disk, and it writes .env only from `environmentFiles`.
#      Thus the values from stage 1 stay.
#
# CAUTION: ~/.hermes holds API keys and OAuth tokens. restic does not back up
# ~/.hermes. See modules/backup.nix.

{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  programs.hermes-agent = {
    enable = true;
    desktop.enable = true;
  };

  # Stage 2. The gateway is a systemd user service that keeps Hermes running
  # for the messaging platforms. hosts/t490/default.nix sets linger, so the
  # service continues after logout.
  #
  # `settings` is empty on purpose. `hermes setup` wrote the provider and
  # the model to config.yaml in stage 1, and the merge keeps those values.
  # `environmentFiles` is empty, so the module does not write .env again.
  # The Telegram token in .env stays.
  #
  # CAUTION: managed mode now blocks `hermes setup` and `hermes config set`.
  # To change the model or the provider, set `settings` here and rebuild.
  services.hermes-agent = {
    enable = true;
    gateway.enable = true;
  };
}
