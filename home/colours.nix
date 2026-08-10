{ config, pkgs, lib, ... }:

# Terminal output, coloured from the same palette as everything else.
#
# The problem this solves: most CLI tools default to "everything is the
# foreground colour", so a wall of output has no structure and you have to
# read it all to find the one line that matters. Colour is the cheapest
# possible index.
#
# Roles are consistent with lib/melancholy.nix, so the meaning carries
# across tools: amber is a number or something noteworthy, red is an error,
# green is success or a type, cyan is something you can act on, grey
# recedes.

let
  t = import ../lib/melancholy.nix;
  hex = c: lib.removePrefix "#" c;
in
{
  # -------------------------------------------------------------------
  # ls / eza
  # -------------------------------------------------------------------
  # vivid generates a full LS_COLORS from a theme file, covering hundreds of
  # file types rather than the dozen the default has. eza reads LS_COLORS.
  home.packages = [ pkgs.vivid ];

  xdg.configFile."vivid/themes/melancholy.yml".text = ''
    colors:
      bg:        '${hex t.bg}'
      fg:        '${hex t.fg}'
      muted:     '${hex t.fgMuted}'
      cyan:      '${hex t.cyan}'
      pink:      '${hex t.pink}'
      green:     '${hex t.green}'
      amber:     '${hex t.amber}'
      red:       '${hex t.red}'
      blue:      '${hex t.blue}'

    core:
      regular_file:
        foreground: fg
      directory:
        foreground: cyan
        font-style: bold
      executable_file:
        foreground: green
        font-style: bold
      symlink:
        foreground: pink
      broken_symlink:
        foreground: red
        font-style: bold
      missing_symlink_target:
        foreground: red
      fifo:
        foreground: amber
      socket:
        foreground: pink
      character_device:
        foreground: amber
      block_device:
        foreground: amber
      normal_text:
        foreground: fg

    text:
      special:
        foreground: amber
      todo:
        foreground: amber
        font-style: bold
      licenses:
        foreground: muted
      configuration:
        foreground: amber
      other:
        foreground: fg

    markup:
      foreground: fg

    programming:
      source:
        foreground: green
      tooling:
        foreground: cyan
        version-control:
          foreground: muted

    media:
      foreground: pink

    office:
      foreground: fg

    archives:
      foreground: red

    executable:
      foreground: green
      font-style: bold

    unimportant:
      foreground: muted
  '';

  programs.zsh.initContent = lib.mkOrder 1200 ''
    # A full LS_COLORS from the melancholy theme. Generated once per shell;
    # vivid is fast enough that caching it is not worth the staleness.
    export LS_COLORS="$(${pkgs.vivid}/bin/vivid generate melancholy 2>/dev/null)"

    # eza reads LS_COLORS for file types, and EZA_COLORS for its own columns.
    # Dates, sizes and permissions should recede; the filename is the point.
    export EZA_COLORS="ur=38;2;112;112;112:uw=38;2;112;112;112:ux=38;2;150;191;51:\
gr=38;2;112;112;112:gw=38;2;112;112;112:gx=38;2;112;112;112:\
tr=38;2;112;112;112:tw=38;2;112;112;112:tx=38;2;112;112;112:\
sn=38;2;255;183;40:sb=38;2;112;112;112:\
da=38;2;112;112;112:uu=38;2;112;112;112:gu=38;2;112;112;112:\
gm=38;2;255;183;40:ga=38;2;150;191;51:gd=38;2;255;105;105:gv=38;2;249;38;114:gt=38;2;0;183;255"

    # less and man. Without these, man pages are a monochrome wall.
    export LESS='-R --use-color'
    export MANROFFOPT='-P -c'
    export GROFF_NO_SGR=1
    export LESS_TERMCAP_md=$'\e[1;38;2;0;183;255m'    # bold  -> cyan
    export LESS_TERMCAP_me=$'\e[0m'
    export LESS_TERMCAP_us=$'\e[4;38;2;255;183;40m'   # underline -> amber
    export LESS_TERMCAP_ue=$'\e[0m'
    export LESS_TERMCAP_so=$'\e[1;38;2;42;42;42;48;2;255;183;40m'  # search hit
    export LESS_TERMCAP_se=$'\e[0m'

    # grep and ripgrep: match in amber on the current line, filename cyan.
    export GREP_COLORS='mt=01;38;2;255;183;40:fn=38;2;0;183;255:ln=38;2;112;112;112:se=38;2;112;112;112'

    # systemd and journald honour this for their own highlighting.
    export SYSTEMD_COLORS=1
  '';

  # -------------------------------------------------------------------
  # ripgrep
  # -------------------------------------------------------------------
  home.file.".config/ripgrep/config".text = ''
    --smart-case
    --colors=match:fg:0xFF,0xB7,0x28
    --colors=match:style:bold
    --colors=path:fg:0x00,0xB7,0xFF
    --colors=line:fg:0x70,0x70,0x70
    --colors=column:fg:0x70,0x70,0x70
  '';
  home.sessionVariables.RIPGREP_CONFIG_PATH =
    "${config.home.homeDirectory}/.config/ripgrep/config";

  # -------------------------------------------------------------------
  # fzf
  # -------------------------------------------------------------------
  programs.fzf.colors = {
    "bg+" = t.bgSubtle;
    bg = t.bg;
    fg = t.fg;
    "fg+" = t.fgString;
    hl = t.amber;
    "hl+" = t.amber;
    info = t.fgMuted;
    prompt = t.cyan;
    pointer = t.pink;
    marker = t.green;
    spinner = t.amber;
    header = t.fgMuted;
    border = t.bgSubtle;
  };

  # -------------------------------------------------------------------
  # zsh syntax highlighting
  # -------------------------------------------------------------------
  # The defaults are green-on-anything, which tells you nothing. This makes
  # the prompt itself informative: a command that does not exist is red
  # BEFORE you press enter.
  programs.zsh.syntaxHighlighting.styles = {
    unknown-token = "fg=#FF6969,bold";
    reserved-word = "fg=#F92672";
    alias = "fg=#00B7FF";
    suffix-alias = "fg=#00B7FF";
    global-alias = "fg=#00B7FF";
    builtin = "fg=#00B7FF";
    function = "fg=#00B7FF";
    command = "fg=#96BF33";
    precommand = "fg=#96BF33,italic";
    commandseparator = "fg=#F92672";
    hashed-command = "fg=#96BF33";
    path = "fg=#DEDEDE,underline";
    globbing = "fg=#FFB728";
    single-quoted-argument = "fg=#E8E8E8";
    double-quoted-argument = "fg=#E8E8E8";
    dollar-quoted-argument = "fg=#E8E8E8";
    command-substitution = "fg=#FFB728";
    process-substitution = "fg=#FFB728";
    back-quoted-argument = "fg=#FFB728";
    assign = "fg=#FFB728";
    redirection = "fg=#F92672";
    comment = "fg=#707070,italic";
    named-fd = "fg=#707070";
    numeric-fd = "fg=#707070";
    arg0 = "fg=#96BF33";
  };

  # Autosuggestions should be clearly a suggestion, not text you typed.
  programs.zsh.autosuggestion.highlight = "fg=#707070";
}
