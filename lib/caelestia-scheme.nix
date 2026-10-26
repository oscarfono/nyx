# Renders lib/melancholy.nix into a caelestia colour scheme.
#
# caelestia reads a scheme from a plain text file of `key value` lines, where
# each value is a hex colour with NO leading hash. The file lives at
#
#   <caelestia-cli>/data/schemes/<name>/<flavour>/<mode>.txt
#
# inside the caelestia-cli package, and caelestia reads no directory under
# $HOME. So home/caelestia.nix overrides the package to add this file. The
# name then appears in `caelestia scheme set -n`.
#
# The scheme needs 109 keys. melancholy has 16 colours, so this file derives
# the rest. Each derived colour is a mix of 2 melancholy colours, which keeps
# lib/melancholy.nix as the single source of colour truth.
#
# The `term0` to `term15` keys take the melancholy ANSI set without a change.

{ lib }:

let
  t = import ./melancholy.nix;

  # ------------------------------------------------------------------
  # Hex arithmetic
  # ------------------------------------------------------------------
  # Nix has no colour type, so these 4 functions do the work. Each one
  # takes and gives a 2-character hex string or an integer from 0 to 255.
  digits = "0123456789abcdef";

  hexVal = c:
    let i = lib.strings.stringLength (lib.head (lib.splitString c digits));
    in i;

  # "2a" -> 42
  hexToInt = s:
    let l = lib.toLower s;
    in (hexVal (builtins.substring 0 1 l)) * 16 + (hexVal (builtins.substring 1 1 l));

  # 42 -> "2a". Clamps, because a mix can overshoot by 1 on a rounding.
  intToHex = n:
    let c = if n < 0 then 0 else if n > 255 then 255 else n;
    in (builtins.substring (c / 16) 1 digits) + (builtins.substring (lib.mod c 16) 1 digits);

  # "#2A2A2A" -> { r = 42; g = 42; b = 42; }
  parts = c:
    let h = builtins.substring 1 6 c;
    in {
      r = hexToInt (builtins.substring 0 2 h);
      g = hexToInt (builtins.substring 2 2 h);
      b = hexToInt (builtins.substring 4 2 h);
    };

  # Strip the hash. caelestia rejects a value that carries one.
  bare = c: lib.toLower (builtins.substring 1 6 c);

  # mix a b pct: pct is how much of b to take, from 0 to 100. Integer only,
  # because Nix floats do not round-trip through builtins.substring.
  mix = a: b: pct:
    let
      A = parts a;
      B = parts b;
      m = x: y: intToHex (x + ((y - x) * pct) / 100);
    in
    (m A.r B.r) + (m A.g B.g) + (m A.b B.b);

  # ------------------------------------------------------------------
  # The mapping
  # ------------------------------------------------------------------
  # amber is the melancholy signature colour, so amber is the M3 primary.
  # cyan is the secondary, pink is the tertiary, red is the error and green
  # is the success. The surface ladder runs from bg up to bgSubtle.
  scheme = {
    # Palette key colours. M3 derives a tonal palette from each one.
    primary_paletteKeyColor = bare t.amber;
    secondary_paletteKeyColor = bare t.cyan;
    tertiary_paletteKeyColor = bare t.pink;
    neutral_paletteKeyColor = bare t.fgMuted;
    neutral_variant_paletteKeyColor = mix t.fgMuted t.bgSubtle 50;

    # Backgrounds, and the ladder of raised surfaces.
    background = bare t.bg;
    onBackground = bare t.fg;
    surface = bare t.bg;
    surfaceDim = mix t.bg "#000000" 15;
    surfaceBright = bare t.bgSubtle;
    surfaceContainerLowest = mix t.bg "#000000" 25;
    surfaceContainerLow = mix t.bg "#000000" 10;
    surfaceContainer = bare t.bg;
    surfaceContainerHigh = mix t.bg t.bgSubtle 35;
    surfaceContainerHighest = mix t.bg t.bgSubtle 60;
    onSurface = bare t.fg;
    surfaceVariant = bare t.bgSubtle;
    onSurfaceVariant = mix t.fg t.fgMuted 30;
    inverseSurface = bare t.fg;
    inverseOnSurface = bare t.bg;
    outline = bare t.fgMuted;
    outlineVariant = mix t.bg t.bgSubtle 60;
    shadow = "000000";
    scrim = "000000";
    surfaceTint = bare t.amber;

    # Primary: amber.
    primary = bare t.amber;
    onPrimary = bare t.bg;
    primaryContainer = mix t.amber t.bg 55;
    onPrimaryContainer = bare t.brightAmber;
    inversePrimary = mix t.amber t.bg 70;
    primaryFixed = bare t.brightAmber;
    primaryFixedDim = bare t.amber;
    onPrimaryFixed = bare t.bg;
    onPrimaryFixedVariant = mix t.bg t.amber 25;

    # Secondary: cyan.
    secondary = bare t.cyan;
    onSecondary = bare t.bg;
    secondaryContainer = mix t.cyan t.bg 60;
    onSecondaryContainer = bare t.brightCyan;
    secondaryFixed = bare t.brightCyan;
    secondaryFixedDim = bare t.cyan;
    onSecondaryFixed = bare t.bg;
    onSecondaryFixedVariant = mix t.bg t.cyan 25;

    # Tertiary: pink.
    tertiary = bare t.pink;
    onTertiary = bare t.bg;
    tertiaryContainer = mix t.pink t.bg 60;
    onTertiaryContainer = bare t.palePink;
    tertiaryFixed = bare t.palePink;
    tertiaryFixedDim = bare t.brightPink;
    onTertiaryFixed = bare t.bg;
    onTertiaryFixedVariant = mix t.bg t.pink 25;

    # Error: red.
    error = bare t.red;
    onError = bare t.bg;
    errorContainer = mix t.red t.bg 60;
    onErrorContainer = bare t.brightRed;

    # Success: green. caelestia adds these 4 keys to the M3 set.
    success = bare t.green;
    onSuccess = bare t.bg;
    successContainer = mix t.green t.bg 60;
    onSuccessContainer = bare t.brightGreen;

    # The 16 ANSI colours, straight from melancholy.
    term0 = bare t.ansi.color0;
    term1 = bare t.ansi.color1;
    term2 = bare t.ansi.color2;
    term3 = bare t.ansi.color3;
    term4 = bare t.ansi.color4;
    term5 = bare t.ansi.color5;
    term6 = bare t.ansi.color6;
    term7 = bare t.ansi.color7;
    term8 = bare t.ansi.color8;
    term9 = bare t.ansi.color9;
    term10 = bare t.ansi.color10;
    term11 = bare t.ansi.color11;
    term12 = bare t.ansi.color12;
    term13 = bare t.ansi.color13;
    term14 = bare t.ansi.color14;
    term15 = bare t.ansi.color15;

    # Catppuccin names. Some caelestia widgets read these keys directly, so
    # a scheme that leaves them out loses colour in those widgets.
    rosewater = bare t.palePink;
    flamingo = bare t.brightPink;
    pink = bare t.brightPink;
    mauve = bare t.pink;
    red = bare t.red;
    maroon = bare t.brightRed;
    peach = bare t.amber;
    yellow = bare t.brightAmber;
    green = bare t.green;
    teal = bare t.brightCyan;
    sky = bare t.brightBlue;
    sapphire = bare t.cyan;
    blue = bare t.blue;
    lavender = bare t.palePink;

    # Text ladder, from the brightest to the most recessed.
    text = bare t.fg;
    subtext1 = mix t.fg t.fgMuted 40;
    subtext0 = bare t.fgMuted;
    overlay2 = mix t.fgMuted t.bgSubtle 25;
    overlay1 = mix t.fgMuted t.bgSubtle 50;
    overlay0 = mix t.fgMuted t.bgSubtle 75;
    surface2 = mix t.bg t.bgSubtle 75;
    surface1 = mix t.bg t.bgSubtle 50;
    surface0 = mix t.bg t.bgSubtle 25;
    base = bare t.bg;
    mantle = mix t.bg "#000000" 10;
    crust = mix t.bg "#000000" 20;

    # KDE link colours, for a Qt application that reads a colour scheme.
    klink = bare t.cyan;
    klinkSelection = bare t.cyan;
    kvisited = bare t.pink;
    kvisitedSelection = bare t.pink;
    knegative = bare t.red;
    knegativeSelection = bare t.red;
    kneutral = bare t.amber;
    kneutralSelection = bare t.amber;
    kpositive = bare t.green;
    kpositiveSelection = bare t.green;
  };
in
{
  inherit scheme;

  # The file content, as caelestia wants it.
  text = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} ${v}") scheme) + "\n";
}
