# Musique du jeu

Chaque dossier ici est une playlist. Dépose des fichiers `.ogg`, `.mp3` ou `.wav` dedans : le jeu les trouve tout seul.

- `menu/` : tous les écrans du menu (et l'éditeur de map)
- `arene/` : pendant une partie sur l'Arène (et sur les maps faites dans l'éditeur)

Les morceaux passent dans l'ordre de leur nom (`01-...`, `02-...`), puis la playlist recommence.
Un dossier vide = pas de musique. Une nouvelle map aura son dossier au nom de sa scène (ex. `scenes/maps/volcan.tscn` → `musique/volcan/`).
Voir `scripts/music.gd`.
