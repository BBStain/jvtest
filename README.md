# Brawler du Swag

Prototype de jeu de combat 2D en plateformes, inspiré de Brawlhalla, fait avec **Godot 4.3**.

**Jouer dans le navigateur (téléphone ou ordinateur) : https://bbstain.github.io/jvtest/**

## Les règles

- 2 joueurs (le code est prêt pour 4), chacun a **3 vies**.
- Un coup reçu = une vie perdue. Tomber hors de la map = une vie perdue, et on réapparaît au milieu.
- Après un coup, on clignote : on est invincible un court instant et on ne peut pas attaquer.
- L'attaque part toujours vers l'adversaire le plus proche. S'il est trop loin, elle frappe dans le vide.
- Si deux attaques se touchent, elles s'annulent et les deux joueurs sont repoussés.
- Pendant un dash, on ne peut pas être touché, mais on ne peut pas attaquer.
- La partie s'arrête quand il ne reste qu'un joueur en vie.

## Les commandes

| Action | Manette | Clavier joueur 1 | Clavier joueur 2 |
|---|---|---|---|
| Se déplacer | Stick gauche ou croix | Z Q S D | Flèches |
| Sauter (2 fois en l'air) | A | Espace | L |
| Attaquer | X | F | K |
| Dash (dans la direction du stick) | Gâchette gauche (ou LB) | G | J |
| Descendre d'une plateforme | Bas | S | Flèche bas |
| Rejouer à la fin | Start ou A | Entrée | Entrée |

- Garder le saut appuyé = saut plus haut. Le lâcher tôt = petit saut.
- En l'air, on a droit à un seul dash avant de retoucher le sol. Un dash vers le haut sert de 3e saut.
- La 1re manette connectée est le joueur 1, la 2e le joueur 2.

## Jouer sur ton téléphone avec une manette Bluetooth

1. Connecte ta manette au téléphone dans les réglages Bluetooth du téléphone.
2. Ouvre le lien du jeu dans Chrome (ou Safari sur iPhone) et tourne le téléphone à l'horizontale.
3. Appuie sur un bouton de la manette : le message « Appuie sur un bouton… » disparaît, c'est prêt.

Avec une seule manette, le joueur 2 reste immobile : il sert de cible d'entraînement.

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

Appuie sur **F5**, ou clique sur le triangle ▶ en haut à droite. Une fenêtre s'ouvre avec le jeu.
Tu peux jouer au clavier ou brancher une manette. Ferme la fenêtre pour revenir à l'éditeur.

### 5. Modifier le jeu

- **Le ressenti des personnages** (vitesse, hauteur de saut, dash, durée des attaques…) :
  ouvre `scripts/fighter.gd` dans le panneau « Système de fichiers » en bas à gauche.
  En haut du fichier, chaque réglage est une ligne `const` avec une explication. Change un chiffre, fais **Ctrl+S**, puis **F5** pour tester.
- **La map** : ouvre `scenes/main.tscn`. Dans l'arbre à gauche, sous `Map`, clique sur `Sol`, `PlateformeMilieu` ou `PlateformeHaut`
  et déplace-les avec la souris dans la vue du milieu. Attention, chaque plateforme a deux enfants à garder de la même taille :
  `Collision` (la forme qui bloque) et `Visuel` (le rectangle de couleur).
- **Le nombre de joueurs** : dans `scripts/game.gd`, change `PLAYER_COUNT := 2`.

## Comment le code est organisé

| Fichier | Rôle |
|---|---|
| `scenes/main.tscn` | La scène principale : la map, les points d'apparition, l'écran de fin |
| `scripts/game.gd` | Crée les joueurs, gère les coups, les chocs d'attaques, les chutes et la fin de partie |
| `scripts/fighter.gd` | Un combattant : déplacements, saut, dash, attaque, vies, dessin |
| `scripts/input/` | Les commandes de chaque joueur, séparées du reste pour pouvoir ajouter le jeu en ligne plus tard |
| `tests/` | Un test automatique qui simule des parties et vérifie les règles |
| `.github/workflows/web.yml` | Construit la version web et la publie sur GitHub Pages à chaque modification de `main` |
