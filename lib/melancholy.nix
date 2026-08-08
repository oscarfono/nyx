# Nyx theme: melancholy.
#
# Single source of truth for colour across the whole desktop. Every module
# that draws anything imports this file. Adding a second theme means adding
# a sibling file with the same attribute names and switching one import.
#
# Palette and role assignments come from oscarfono/melancholy-theme, so the
# desktop and Emacs agree without either one being special-cased.

rec {
  name = "melancholy";

  # Core
  bg        = "#2A2A2A";   # base background
  bgSubtle  = "#4A4A4A";   # regions, source blocks, selection
  fg        = "#DEDEDE";   # default text
  fgString  = "#E8E8E8";   # softened, for strings
  fgMuted   = "#707070";   # comments, borders, anything that recedes

  # Roles
  cyan   = "#00B7FF";   # functions, builtins, things you call
  pink   = "#F92672";   # keywords, operators, active elements
  green  = "#96BF33";   # types, variables, success
  amber  = "#FFB728";   # numbers, constants, warnings. The signature colour.
  red    = "#FF6969";   # errors, danger
  palePink = "#FCDEEA";

  accent = amber;

  # Bright variants, derived for the 16-colour ANSI set
  brightRed    = "#FF8B8B";
  brightGreen  = "#B4DC4E";
  brightAmber  = "#FFC85A";
  brightBlue   = "#4FCBFF";
  brightPink   = "#FC5C8D";
  brightCyan   = "#7FE0FF";
  blue         = "#0091CC";   # darkened cyan so blue and cyan are distinct

  # Hyprland wants rgba() without the hash
  hypr = c: "rgba(" + (builtins.substring 1 6 c) + "ee)";

  # 16-colour ANSI set, for any terminal or tool that wants one
  ansi = {
    color0 = bg;          color8  = fgMuted;
    color1 = red;         color9  = brightRed;
    color2 = green;       color10 = brightGreen;
    color3 = amber;       color11 = brightAmber;
    color4 = blue;        color12 = brightBlue;
    color5 = pink;        color13 = brightPink;
    color6 = cyan;        color14 = brightCyan;
    color7 = fg;          color15 = fgString;
  };
}
