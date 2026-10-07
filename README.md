# Brawler du Swag

Prototype de jeu de combat 2D en plateformes, inspiré de Brawlhalla, fait avec **Godot 4.3**.

**Jouer dans le navigateur (téléphone ou ordinateur) : https://bbstain.github.io/jvtest/**

## Avant la partie : l'écran de connexion

Chaque joueur se connecte avec son appareil, puis on lance la partie (il faut au moins 2 joueurs, jusqu'à 4) :

- **Manette** : appuie sur **A** pour rejoindre, **B** pour partir.
- **Clavier** : deux joueurs peuvent partager un clavier. **Espace** pour le côté gauche (Z Q S D), **L** pour le côté droit (flèches). **Échap** retire le dernier joueur clavier.
- **Lancer la partie** : clique sur le bouton, ou appuie sur **Start** / **Entrée**.

À la fin d'une partie : **Start** ou **A** pour rejouer, **B** ou **Échap** pour revenir à cet écran.

La caméra suit les joueurs : elle dézoome quand ils s'éloignent et zoome quand ils se rapprochent.

## Les règles

- **La map** : au centre, le sol avec ses deux plateformes et un mur de chaque côté. À gauche, une zone aérienne de pylônes flottants où l'on saute de mur en mur. À droite, une grande zone plate pour les duels directs.

- 2 joueurs (le code est prêt pour 4), chacun a **3 vies**.
- Un coup reçu = une vie perdue. Tomber hors de la map = une vie perdue, et on réapparaît au milieu.
- Après un coup, on clignote : on est invincible un court instant et on ne peut pas attaquer.
- L'attaque légère part toujours vers l'adversaire le plus proche. S'il est trop loin, elle frappe dans le vide.
- Si deux attaques se touchent, elles s'annulent et les deux joueurs sont repoussés. Une marque apparaît à l'endroit du choc et s'efface en quelques secondes (orange si une attaque lourde a été contrée).
- L'**attaque lourde** part du dessus de la tête et fait un arc de cercle jusqu'aux pieds, devant soi. Elle est plus lente et projette plus fort.
- Contrer une attaque lourde avec une attaque légère annule les deux, mais le temps de recharge de celui qui a contré est doublé pour cette fois.
- Pendant un dash, on ne peut pas être touché, mais on ne peut pas attaquer.
- La partie s'arrête quand il ne reste qu'un joueur en vie.

## Les commandes

| Action | Manette | Clavier joueur 1 | Clavier joueur 2 |
|---|---|---|---|
| Se déplacer | Stick gauche ou croix | Z Q S D | Flèches |
| Sauter (2 fois en l'air) | A | Espace | L |
| Attaque légère | X | F | K |
| Attaque lourde | Y | R | I |
| Dash (dans la direction du stick) | Gâchette gauche (ou LB) | G | J |
| Descendre d'une plateforme | Bas | S | Flèche bas |
| Rejouer à la fin | Start ou A | Entrée | Entrée |
| Revenir au menu à la fin | B | Échap | Échap |

- Garder le saut appuyé = saut plus haut. Le lâcher tôt = petit saut.
- En l'air, on a droit à un seul dash avant de retoucher le sol. Un dash vers le haut sert de 3e saut.
- **Murs** : en l'air, pousse le stick vers un mur pour t'y coller. Tu glisses doucement vers le bas, et tes 2 sauts et ton dash sont rechargés. Saute pour rebondir dans l'autre sens.
- Le premier qui rejoint sur l'écran de connexion est le joueur 1, le suivant le joueur 2, etc.

## Jouer sur ton téléphone avec une manette Bluetooth

1. Connecte ta manette au téléphone dans les réglages Bluetooth du téléphone.
2. Ouvre le lien du jeu dans Chrome (ou Safari sur iPhone) et tourne le téléphone à l'horizontale.
3. Appuie sur **A** : ta manette apparaît dans la case du joueur 1.

Sur ordinateur, la manette PS5 marche dans Chrome ou Edge, mais Firefox la reconnaît mal.

## Guide débutant : ouvrir le projet sur ton ordinateur

### 1. Installer Godot

1. Va sur https://godotengine.org/download/archive/4.3-stable/
2. Télécharge la version **Standard** pour ton système (Windows, macOS ou Linux). Pas la version « .NET ».
3. Sur Windows, c'est un fichier `.zip` : fais clic droit > Extraire tout, puis lance `Godot_v4.3-stable_win64.exe`.
   Il n'y a rien à installer, le programme se lance directement.

Une version plus récente de Godot marche aussi, mais elle te proposera de convertir le projet. Avec la 4.3, tout est identique à ce qui tourne en ligne.

### 2. Récupérer le projet

1. Sur la page GitHub du dépôt, clique sur le bouton vert **Code**, puis **Download ZIP**.
2. Extrais le zip dans un dossier facile à retrouver, par exemple `Documents/jvtest`.

(Plus tard, pour envoyer tes propres modifications, on installera GitHub Desktop ensemble.)

### 3. Ouvrir le projet dans Godot

1. Lance Godot : la fenêtre « Gestionnaire de projets » s'ouvre.
2. Clique sur **Importer**, va dans le dossier extrait et choisis le fichier `project.godot`.
3. Clique sur **Importer et éditer**. L'éditeur s'ouvre (le premier chargement prend quelques secondes).

Si Godot est en anglais : Editor > Editor Settings > Interface > Editor > Editor Language > `fr`, puis redémarre Godot.

### 4. Lancer le jeu

Appuie sur **F5**, ou clique sur le triangle ▶ en haut à droite. Une fenêtre s'ouvre sur l'écran de connexion.
Astuce : ouvre `scenes/main.tscn` et appuie sur **F6** pour aller directement au combat (joueur 1 = Z Q S D ou manette 1, joueur 2 = flèches ou manette 2).
Tu peux jouer au clavier ou brancher une manette. Ferme la fenêtre pour revenir à l'éditeur.

### 5. Modifier le jeu

- **Le ressenti des personnages** (vitesse, hauteur de saut, dash, durée des attaques…) :
  ouvre `scripts/fighter.gd` dans le panneau « Système de fichiers » en bas à gauche.
  En haut du fichier, chaque réglage est une ligne `const` avec une explication. Change un chiffre, fais **Ctrl+S**, puis **F5** pour tester.
- **La map** : ouvre `scenes/main.tscn`. Dans l'arbre à gauche, sous `Map`, clique sur `Sol`, `PlateformeMilieu`, `PlateformeHaut`, `MurGauche` ou `MurDroit`
  et déplace-les avec la souris dans la vue du milieu. Attention, chaque plateforme a deux enfants à garder de la même taille :
  `Collision` (la forme qui bloque) et `Visuel` (le rectangle de couleur).
- **La caméra** : en haut de `scripts/game.gd`, les réglages `CAMERA_...` (marge autour des joueurs, zoom le plus proche et le plus éloigné, vitesse).

## Comment le code est organisé

| Fichier | Rôle |
|---|---|
| `scenes/lobby.tscn` + `scripts/lobby.gd` | L'écran de connexion des joueurs |
| `scripts/game_setup.gd` | Retient quel appareil va avec quel joueur entre l'écran de connexion et le combat |
| `scenes/main.tscn` | Le combat : la map, les points d'apparition, la caméra, l'écran de fin |
| `scripts/game.gd` | Crée les joueurs, gère les coups, les chocs d'attaques, les chutes, la caméra et la fin de partie |
| `scripts/fighter.gd` | Un combattant : déplacements, saut, dash, attaque, vies, dessin |
| `scripts/input/` | Les commandes de chaque joueur, séparées du reste pour pouvoir ajouter le jeu en ligne plus tard |
| `tests/` | Un test automatique qui simule des parties et vérifie les règles |
| `.github/workflows/web.yml` | Construit la version web et la publie sur GitHub Pages à chaque modification de `main` |
