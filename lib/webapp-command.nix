# The command that starts one web app. ONE definition, two consumers:
# home/webapps.nix writes it into a .desktop file, and lib/menu.nix writes
# it into a menu dispatch script.
#
# Each argument is quoted IN WHOLE. The Desktop Entry specification permits
# no other form, and fuzzel obeys the specification. An earlier version
# wrote --app="<url>", which quotes only part of the argument. A shell
# accepts that form, so the menu started the web app. fuzzel rejected the
# same line with:
#
#   command line contains non-specification-compliant quoting
#   (arguments must be quoted in whole)
#
# fuzzel gives no message on screen when the line is bad. The launcher
# looks like it does nothing. Keep the quotes around the WHOLE argument.
#
# CAUTION: the specification reserves ? & ; $ * ~ | < > ( ) # and the
# backquote. A URL that contains one of these characters needs an escape
# before you put the URL in an entry.

app: ''brave "--app=${app.url}" "--class=${app.class}"''
