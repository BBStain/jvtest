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

- **La map** : elle monte haut ! Au centre, le sol avec quatre plateformes, puis des étages de plateformes jusqu'à un sommet, et un grand mur de chaque côté. À gauche, une zone aérienne de pylônes flottants et de petites corniches, avec des pylônes jusqu'en haut, deux ascenseurs qui montent et descendent et une navette qui passe en bas pour rattraper ceux qui tombent. À droite, une zone de duel avec deux petites marches, des étages de plateformes, deux navettes en hauteur et un grand mur au bout. Les plateformes violettes bougent et transportent les joueurs posés dessus.

- 2 joueurs (le code est prêt pour 4), chacun a **3 vies**.
- Un coup reçu = une vie perdue. Tomber hors de la map = une vie perdue, et on réapparaît au milieu.
- Après un coup, on clignote : on est invincible un court instant et on ne peut pas attaquer.
- L'attaque légère part toujours vers l'adversaire le plus proche. S'il est trop loin, elle frappe dans le vide.
- Si deux joueurs se touchent exactement en même temps, c'est aussi un choc : les deux attaques s'annulent et personne ne perd de vie.
- Si deux attaques se touchent, elles s'annulent et les deux joueurs sont repoussés. Une marque apparaît à l'endroit du choc et s'efface en quelques secondes (orange si une attaque lourde a été contrée).
- L'**attaque lourde** part du dessus de la tête et fait un arc de cercle jusqu'aux pieds, devant soi. Elle est plus lente et projette plus fort.
- **Charger l'attaque lourde** : garde Y appuyé. Plus tu charges, plus l'arme grandit (jusqu'à 2 fois plus longue), frappe loin et projette fort. Tu frappes en lâchant Y, ou tout seul au bout d'1 seconde. Pendant la charge tu avances lentement, et pendant la frappe tu es immobilisé.
- Contrer une attaque lourde (pendant sa frappe) avec une attaque légère annule les deux : les deux joueurs sont repoussés loin et ne peuvent plus attaquer pendant 1,4 seconde. C'est un **micro-duel** : la caméra zoome sur eux et le temps ralentit (2 fois moins vite) pendant 5 secondes, ou jusqu'à ce que l'un des deux perde une vie.
- Deux attaques lourdes qui se percutent font une **micro-explosion** qui éjecte fort les deux joueurs, sans perte de vie.
- Pendant un dash, on ne peut pas être touché, mais on ne peut pas attaquer.
- **Blocage** (tenir B) : le personnage s'entoure d'un contour lumineux et a un bouclier de **3 points**. Un coup sur le bouclier ne fait pas perdre de vie : il enlève 1 point (2 pour une attaque lourde), et l'attaquant est repoussé mais peut refrapper tout de suite.
- Pendant le blocage, on avance beaucoup plus lentement, on saute moins haut, et on ne peut ni dasher ni attaquer.
- Si le bouclier casse, on arrête de bloquer et on ne peut plus attaquer pendant 1,5 seconde, mais on peut toujours bouger, sauter et dasher.
- Le bouclier regagne 1 point toutes les 2 secondes quand on ne bloque pas.
- **Course** (tenir LT ou Shift) : on va 1,5 fois plus vite, donc on saute aussi plus loin. Toutes les actions marchent en courant.
- Courir vide une **jauge d'endurance**, qui apparaît à côté du perso, du côté opposé à l'adversaire. Bloquer en courant la vide plus de 2 fois plus vite. Quand on arrête de courir, elle remonte. Si elle est vide, on ne peut plus courir tant qu'elle n'est pas remontée un peu.
- La partie s'arrête quand il ne reste qu'un joueur en vie.

## Les commandes

| Action | Manette | Clavier joueur 1 | Clavier joueur 2 |
|---|---|---|---|
| Se déplacer | Stick gauche ou croix | Z Q S D | Flèches |
| Sauter (2 fois en l'air) | A | Espace | L |
| Attaque légère | X | F | K |
| Attaque lourde (garder pour charger) | Y | R | I |
| Dash (dans la direction du stick) | LB | G | J |
| Courir (maintenir) | Gâchette gauche LT | Shift gauche | Shift droit |
| Bloquer (maintenir) | B | C | U |
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

- **Un personnage** (vitesse, hauteur de saut, dash, attaques, poids…) : double-clique sur `characters/barre.tres`
  dans le panneau « Système de fichiers » en bas à gauche. Ses réglages s'affichent à droite dans l'inspecteur, rangés par groupes
  (Déplacement, Dash, Attaque légère…). Change un chiffre, fais **Ctrl+S**, puis **F5** pour tester.
- **Ajouter un personnage** : clic droit sur `characters/barre.tres` > Dupliquer, donne-lui un nom, change ses réglages,
  puis ajoute son chemin dans la liste `CHARACTERS` de `scripts/game_setup.gd`.
- **Les règles communes à tous** (bouclier, contre, invincibilité…) : en haut de `scripts/fighter.gd`, chaque règle est une ligne `const` avec une explication.
- **La map** : ouvre `scenes/maps/arene.tscn`. Dans l'arbre à gauche, clique sur `Sol`, `PlateformeMilieu`, `PlateformeHaut`, `MurGauche`, `MurDroit`
  ou une pièce de `ZoneAerienne` / `ZoneDuel`, et déplace-les avec la souris dans la vue du milieu. Attention, chaque plateforme a deux enfants à garder de la même taille :
  `Collision` (la forme qui bloque) et `Visuel` (le rectangle de couleur).
  Les plateformes mobiles (`Ascenseur`, `AscenseurHaut`, `NavetteBasse`, `NavetteHaute`, `NavetteSommet`) se règlent à droite dans l'inspecteur :
  `size` (taille), `travel` (trajet) et `period` (durée d'un aller-retour en secondes).
- **Ajouter une map** : clic droit sur `scenes/maps/arene.tscn` > Dupliquer, change le décor (garde les nœuds `SpawnPoints` et `RespawnPoint`),
  puis ajoute son chemin dans la liste `MAPS` de `scripts/game_setup.gd`. La zone hors de laquelle on tombe se règle dans l'inspecteur (`blast_zone`).
- **La caméra** : en haut de `scripts/game.gd`, les réglages `CAMERA_...` (marge autour des joueurs, zoom le plus proche et le plus éloigné, vitesse).

## Prochaines étapes

1. Utiliser le moteur de temps (`scripts/time_engine.gd`) pour d'autres moments forts (ralentis et accélérations).
2. Un menu (écran titre, commandes, options).
3. Des attaques spéciales avec des combinaisons de touches.
4. Le jeu en ligne.

## Comment le code est organisé

| Fichier | Rôle |
|---|---|
| `scenes/lobby.tscn` + `scripts/lobby.gd` | L'écran de connexion des joueurs |
| `scripts/game_setup.gd` | La liste des maps et des personnages, et les choix des joueurs (appareil, personnage, map) |
| `scenes/main.tscn` | Le combat : la caméra et l'écran de fin (la map est chargée à part) |
| `scenes/maps/` + `scripts/game_map.gd` | Les maps : le décor, les points d'apparition et la zone de jeu |
| `characters/` + `scripts/character_stats.gd` | Les personnages et leurs caractéristiques (vitesse, sauts, attaques, poids…) |
| `scripts/game.gd` | Crée les joueurs, gère les coups, les chocs d'attaques, les chutes, la caméra et la fin de partie |
| `scripts/fighter.gd` | Un combattant : déplacements, saut, dash, attaques, blocage, vies, dessin, et les règles communes |
| `scripts/moving_platform.gd` | Une plateforme qui fait des allers-retours |
| `scripts/clash_mark.gd` | La marque laissée sur le terrain quand deux attaques se contrent |
| `scripts/micro_explosion.gd` | La micro-explosion quand deux attaques lourdes se percutent |
| `scripts/time_engine.gd` | Le moteur de temps : ralentit ou accélère tout le jeu pendant un moment |
| `scripts/input/` | Les commandes de chaque joueur, séparées du reste pour pouvoir ajouter le jeu en ligne plus tard |
| `tests/` | Un test automatique qui simule des parties et vérifie les règles |
| `.github/workflows/web.yml` | Construit la version web et la publie sur GitHub Pages à chaque modification de `main` |
