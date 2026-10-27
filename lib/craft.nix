# The ArtCraft apps, as data.
#
# modules/craft.nix installs each app from this table. home/dock.nix puts
# each app on the dock. Thus a new entry here gives a new app in both
# places.
#
# Each name is also the GitHub repository under github.com/storytold.
# Each app has the desktop ID and the window class
# ai.storyteller.<name>. See modules/craft.nix for the update procedure.

{
  photocraft  = { version = "0.16.0"; hash = "sha256-fBfzYz6/favydiji0mN9kYx8KlsWO4uQNHp4rN32Ngg="; };
  lightcraft  = { version = "0.14.0"; hash = "sha256-uCM7k3PW6ZsRgMHDn9yxPUnEQfgAkncIMfqxlcTE/aI="; };
  vectorcraft = { version = "0.17.0"; hash = "sha256-ZsKJ0L01S3HkzXhxk+oEgeOhzSOfKhgGgRDqNoUvwCY="; };
  designcraft = { version = "0.13.0"; hash = "sha256-UxTUa8Ugz1SDWi0SkzUb4f7RFiKOBVOTAZcp8E4PmcI="; };
  pdfcraft    = { version = "0.14.0"; hash = "sha256-qT9RHof2MDbKX1MAsaehijzSKFIF3qsVOUyqbug8bx8="; };
  filmcraft   = { version = "0.13.0"; hash = "sha256-QOnWhfs+0bCiHJwCIR8ahJngmkfFUSRM5+6A8lhNOps="; };
  effectcraft = { version = "0.17.0"; hash = "sha256-zXrODXRzS3noUfGFN8FLKVO3/rXaJA9QBeaAVHahUpI="; };
  figcraft    = { version = "0.11.2"; hash = "sha256-adIdDTcXc4+dp50EvIbBUum4+RnmOVrpexy1azbN4rk="; };
  soundcraft  = { version = "0.13.1"; hash = "sha256-Ce5siEWTT+70u/TFwOLw/8o/yREm/XpqQGGx+DkHRW0="; };
}
