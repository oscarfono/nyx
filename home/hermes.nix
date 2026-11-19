{ config, pkgs, inputs, ... }:

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
# ~/.hermes holds API keys and OAuth tokens, and modules/backup.nix DOES back
# it up: /home/<user>/.hermes is in that module's `paths`, caches excepted
# (see the exclude list there).
#
# CORRECTED 19 November 2026. This comment previously said the opposite — that
# restic "does not back up ~/.hermes" — and it was believed: a paper in the
# Liber8 vault recorded the credentials as a single unbacked-up copy, an
# evening's reasoning rested on it, and the error was only caught by reading
# backup.nix rather than this file. The wrong sentence is kept above this
# correction because the mistake is the reason the sentence exists.
#
# The real single point of failure is one line further on, and it is worth
# naming here so the next reader does not have to find it: the restic
# repository password lives in sops, backup.nix warns that losing it loses the
# backups, and that makes the AGE KEY the thing to protect — not the data.

let
  projects = "${config.home.homeDirectory}/Projects";

  # The projects that the docker sandbox mounts. Each one appears at the
  # same path under /workspace.
  #
  # nyx is here so the agents can read the module that governs them. The
  # file that decides what the sandbox may reach was, until 19 November
  # 2026, the one project the sandbox could not open — which is how an
  # evening went into working out Hermes's own messaging configuration from
  # documentation while the answer sat one directory away.
  #
  # liber8-floor is the Liber8 floor application's repository (see
  # home/liber8-floor.nix). Neither project holds a plain-text secret: no
  # .env, no key file, nothing that maskedSecrets below would need to
  # cover. That check is required by the caution directly below, and it was
  # made before these two were added.
  mountedProjects = [
    "liber8"
    "liber8-floor"
    "nyx"
    "polaris1"
    "adp"
    "adp-tuned"
    "adp-flash"
    "bgb"
  ];

  # The plain-text secrets in the mounted projects. In the container, an
  # empty read-only file covers each one. The file on the host does not
  # change.
  #
  # CAUTION: a secret file that is not in this list is visible to the
  # agents. Before you add a project above, find its secret files, and
  # add each one here.
  maskedSecrets = [
    "adp/.env"
    "polaris1/app/deploy/.env"
    "polaris1/station/deploy/.env"
  ];

  emptyFile = pkgs.writeText "hermes-masked-secret" "";
in
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

    # `hermes setup` selected the docker terminal backend. The unit PATH
    # has only Hermes, bash, coreutils and git, so the gateway did not
    # find docker. The account is in the docker group, so the CLI is
    # sufficient.
    extraPackages = [ pkgs.docker ];

    # `hermes setup` set proxy.enabled to true, but the iron-proxy egress
    # proxy was never configured. With enforce_on_docker (the default), the
    # docker backend then refuses to start a sandbox, and each terminal and
    # file tool fails. false is the default of Hermes, and starts nothing.
    settings.proxy.enabled = false;

    # The docker sandbox sees only the projects in mountedProjects, at
    # /workspace/<name>. The other projects in ~/Projects stay out of the
    # sandbox. When all of ~/Projects was mounted, the agents read the
    # deploy .env files of polaris1. maskedSecrets covers those files now.
    #
    # cwd is a path in the container. hosts/t490/default.nix links
    # /workspace on the host to ~/Projects, so the same path is correct
    # on the host.
    settings.terminal.cwd = "/workspace/liber8";
    settings.terminal.docker_volumes =
      map (name: "${projects}/${name}:/workspace/${name}") mountedProjects
      ++ map (path: "${emptyFile}:/workspace/${path}:ro") maskedSecrets
      ++ [
        "${config.home.homeDirectory}/.hermes/github:/opt/github:ro"

        # The Vultr API key, read-only, for the same reason the GitHub token is
        # here: the agent cannot fix infrastructure it cannot reach, and on
        # 19 November 2026 an evening went into a stuck instance that one API
        # call would have cleared. The file is ~/.hermes/vultr/token, outside
        # the Nix store and outside every repository, and it is populated by
        # the Director from the existing key — never typed into a chat, because
        # the transcript is permanent.
        #
        # CAUTION: BIGGER BLAST RADIUS THAN THE GITHUB TOKEN, and it is worth
        # stating in the file rather than in a memory. The GitHub token is
        # scoped to one repository. A Vultr key is ACCOUNT-WIDE and can destroy
        # every instance on it — including polaris1's, if there are any. Vultr
        # does not, as far as this desk verified on 19 November 2026, offer
        # scoped or read-only keys.
        #
        # So this mount is all-or-nothing, and three things follow: the key is
        # rotated if the sandbox is ever suspected (policy 09 rule 11); no
        # seat spends on this account without the Director's word; and the
        # script that uses it (liber8/scripts/vultr-triage.sh) confirms a
        # destroy by asking for the instance id to be typed back.
        "${config.home.homeDirectory}/.hermes/vultr:/opt/vultr:ro"
      ];

    # Hermes has its own GitHub credential: a fine-grained token for
    # oscarfono/liber8 only, with Contents read and write. The token is in
    # ~/.hermes/github/token, which is outside the Nix store and outside
    # the vault. The container reads it through the read-only mount above.
    #
    # The container has git but no ssh, so git@github.com: becomes HTTPS.
    # The helper only answers "get". It never writes the token.
    #
    # The agents commit as their own identity, without a signature. The
    # GIT_CONFIG_* values override the signing key in .git/config of the
    # vault. A commit by the Director stays signed.
    #
    # CAUTION: an agent can read the token. Keep its scope to this one
    # repository. Give it an expiry date.
    settings.terminal.docker_env = {
      GIT_CONFIG_COUNT = "5";
      GIT_CONFIG_KEY_0 = "credential.https://github.com.helper";
      GIT_CONFIG_VALUE_0 = "!f() { test \"$1\" = get && echo username=x-access-token && echo password=$(cat /opt/github/token); }; f";
      GIT_CONFIG_KEY_1 = "url.https://github.com/.insteadOf";
      GIT_CONFIG_VALUE_1 = "git@github.com:";
      GIT_CONFIG_KEY_2 = "commit.gpgsign";
      GIT_CONFIG_VALUE_2 = "false";
      GIT_CONFIG_KEY_3 = "user.name";
      GIT_CONFIG_VALUE_3 = "Hermes (liber8)";
      GIT_CONFIG_KEY_4 = "user.email";
      GIT_CONFIG_VALUE_4 = "hermes@liber8.invalid";
    };

    # The hosted MCP server of Cloudflare. It uses OAuth, so no key goes
    # into the Nix store or into .env. Hermes keeps the token in
    # ~/.hermes/mcp-tokens/, and restic backs up that directory.
    #
    # After a rebuild, log in one time:
    #   hermes mcp login cloudflare
    mcpServers = {
      # The full Cloudflare API in Code Mode, and the developer docs.
      cloudflare = {
        url = "https://mcp.cloudflare.com/mcp";
        auth = "oauth";
      };
    };
  };
}
