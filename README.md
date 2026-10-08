# Brawler du Swag

Prototype de jeu de combat 2D en plateformes, inspiré de Brawlhalla, fait avec **Godot 4.3**.

**Jouer dans le navigateur (téléphone ou ordinateur) : https://bbstain.github.io/jvtest/**

Après une mise à jour, le navigateur peut garder l'ancienne version jusqu'à 10 minutes. Pour avoir la nouvelle tout de suite : **Ctrl + F5** sur ordinateur, ou ferme l'onglet et rouvre-le sur téléphone. Le numéro de la version est écrit en petit en bas à droite du menu.

## Avant la partie : le menu

1. **Appuie sur une touche** : le premier qui appuie (manette ou clavier) devient le **joueur 1** et ouvre le menu.
2. **Le menu** a 3 boutons : **JOUER**, **COMMANDES** (le tableau des touches) et **OPTIONS** (le nombre de vies, de 1 à 5).
   Tant qu'on est dans le menu, chaque nouvelle manette ou côté du clavier qui appuie sur une touche devient le joueur suivant (J2, J3, J4).
   Deux joueurs peuvent partager un clavier : côté gauche (Z Q S D) et côté droit (flèches).
3. **JOUER** ouvre le choix du personnage : une case par joueur, avec sa manette ou son clavier. Gauche / droite pour faire défiler les persos, valider pour être prêt. Un joueur qui veut **se retirer** de la partie appuie sur **Y** (manette), **R** (clavier gauche) ou **I** (clavier droit) : les joueurs suivants remontent d'une place.
   Revenir en arrière annule « prêt », ou fait quitter le joueur (le joueur 1 revient au menu). Il faut au moins 2 joueurs.
4. Quand tout le monde est prêt : le choix de la map. Valider lance la partie.

| Dans le menu | Manette | Clavier gauche | Clavier droit |
|---|---|---|---|
| Choisir | Stick ou croix | Z Q S D | Flèches |
| Valider | A ou Start | Espace, F ou Entrée | L ou K |
| Revenir | B | Échap ou C | U ou Retour arrière |

À la fin d'une partie : **Start**, **A** ou **Entrée** pour rejouer, **B** ou **Échap** pour revenir au menu (les joueurs restent connectés).

**Pause** : **Start** sur la manette, **Échap** ou **P** au clavier. Le menu pause propose :
- **Reprendre** : on continue (Start, Échap ou P marchent aussi).
- **Restart** : on recommence la partie avec les mêmes joueurs.
- **Remap** : on échange les manettes entre joueurs. Chacun pousse gauche / droite pour envoyer sa manette (ou son clavier) au joueur d'à côté : par exemple la manette 1 passe au joueur 2, et la manette 2 au joueur 1. La manette vibre quand elle change de joueur.
- **Quitter** : retour au menu.

La caméra suit les joueurs : elle dézoome quand ils s'éloignent et zoome quand ils se rapprochent.

## Les règles

- **La map** : elle monte haut ! Au centre, le sol avec quatre plateformes, puis des étages de plateformes jusqu'à un sommet, et un grand mur de chaque côté. À gauche, une zone aérienne de pylônes flottants et de petites corniches, avec des pylônes jusqu'en haut, deux ascenseurs qui montent et descendent et une navette qui passe en bas pour rattraper ceux qui tombent. À droite, une zone de duel avec deux petites marches, des étages de plateformes, deux navettes en hauteur et un grand mur au bout. Les plateformes violettes bougent et transportent les joueurs posés dessus.

- De 2 à 4 joueurs, chacun a **3 vies** (réglable dans OPTIONS).
- Un coup reçu = une vie perdue. Tomber hors de la map = une vie perdue, et on réapparaît au milieu.
- Après un coup, on clignote : on est invincible un court instant et on ne peut pas attaquer.
- L'attaque légère (X) part vers l'adversaire le plus proche. À la manette, une pichenette sur le **stick droit** lance aussi une attaque légère, mais dans la direction du stick (un coup par pichenette) : pratique à 3 ou 4 pour choisir qui on frappe. C'est comme un coup de poing rapide ou un coup d'épée horizontal : toute la barre touche, même collé à l'adversaire, mais rien derrière soi (à 3 ou 4, celui qui est dans ton dos n'est pas touché, et une attaque dans ton dos n'est pas un contre). S'il est trop loin, elle frappe dans le vide.
- Si deux joueurs se touchent exactement en même temps, c'est aussi un choc : les deux attaques s'annulent et personne ne perd de vie.
- Si deux attaques se touchent, elles s'annulent et les deux joueurs sont repoussés. Une marque apparaît à l'endroit du choc et s'efface en quelques secondes (orange si une attaque lourde a été contrée).
- L'**attaque lourde** part du dessus de la tête et fait un arc de cercle jusqu'aux pieds, devant soi. Elle est plus lente et projette plus fort.
- **Charger l'attaque lourde** : garde Y appuyé. Plus tu charges, plus l'arme grandit (jusqu'à 2 fois plus longue), frappe loin et projette fort. Tu frappes en lâchant Y, ou tout seul quand la charge est pleine (1 seconde, 0,7 pour Jib). Pendant la charge tu avances lentement, et pendant la frappe tu es immobilisé.
- Contrer une attaque lourde (pendant sa frappe) avec une attaque légère annule les deux : les deux joueurs sont repoussés loin. Celui qui a lancé la lourde ne peut plus attaquer pendant **1 seconde**, celui qui a contré peut refrapper **tout de suite**. C'est un **micro-duel** : la caméra zoome sur eux et le temps ralentit (2 fois moins vite) pendant 5 secondes, ou jusqu'à ce que l'un des deux perde une vie. Le ralenti touche tout le monde. À 3 ou 4 joueurs, la caméra garde tous les joueurs à l'écran et se resserre juste un peu.
- **Pendant un ralenti, chaque contre** (attaques qui se percutent, lourde contrée, blocage parfait) **relance le ralenti** pour toute sa durée : plus on se contre, plus le duel au ralenti dure. Pendant un micro-duel, seuls les contres entre les deux duellistes comptent : à 3 ou 4, les autres joueurs ne prolongent pas le ralenti et ne lancent pas de 2e duel.
- Quand on se contre, chacun est repoussé d'autant plus loin que l'autre est **lourd** : un gros perso repousse loin un petit, et recule peu.
- Deux attaques lourdes qui se percutent font une **micro-explosion** qui éjecte fort les deux joueurs, sans perte de vie.
- Pendant un dash, on ne peut pas être touché, mais on ne peut pas attaquer.
- **Blocage** (tenir B) : le personnage s'entoure d'un contour lumineux. Un coup sur le bouclier ne fait pas perdre de vie, et l'attaquant est repoussé mais peut refrapper tout de suite. Mais chaque coup fait **craquer** un peu plus la surbrillance : il faut **20 coups** pour la casser (une attaque lourde compte pour 2).
- **Blocage parfait** : appuie sur B **pile au moment** où le coup arrive (au plus 0,15 seconde avant). C'est un contre : personne ne perd de vie, le bouclier ne craque pas, les deux sont repoussés, une marque bleue apparaît, et celui qui frappait ne peut plus attaquer pendant **1 seconde** alors que toi tu peux riposter tout de suite. Si tu bloquais déjà depuis plus longtemps, c'est un blocage normal.
- Pendant le blocage, on avance beaucoup plus lentement, on saute moins haut, et on ne peut ni dasher ni attaquer.
- Le bouclier se répare lentement quand on ne bloque pas (une fissure en moins toutes les 2 secondes).
- Si le bouclier casse : **ralenti**, les deux joueurs sont éjectés, et celui qui l'a perdu ne peut plus attaquer pendant 2 secondes (il peut toujours bouger, sauter et dasher). Son bouclier reste **cassé jusqu'à la fin de la partie** : il ne peut plus bloquer. (Pendant un micro-duel, le duel continue au ralenti et repart pour toute sa durée.)
- **Course** (tenir LT ou Shift) : on va 1,5 fois plus vite, donc on saute aussi plus loin. Toutes les actions marchent en courant.
- Courir vide une **jauge d'endurance**, qui apparaît à côté du perso, du côté opposé à l'adversaire. Bloquer en courant la vide 2,33 fois plus vite (pour chaque perso). Quand on arrête de courir, elle remonte. Si elle est vide, on ne peut plus courir tant qu'elle n'est pas remontée un peu.
- La partie s'arrête quand il ne reste qu'un joueur en vie.

### Les personnages

| | Barre | Jumb | Jib |
|---|---|---|---|
| Taille | normale | plus grand et plus large | plus petit |
| Poids (calculé selon la taille) | 1 | 1,4 : recule moins, repousse plus | 0,78 : recule plus, repousse moins |
| Vitesse | normale | plus lent | plus rapide |
| Saut | normal | un tout petit peu moins haut | plus haut |
| Attaques | normales | plus longues, projettent plus loin | plus courtes, projettent moins loin |
| Dash | normal | même longueur, plus lent | même longueur, plus rapide |
| Endurance (course) | normale | se vide plus vite | se vide plus lentement |
| Attaque lourde | charge pleine en 1 s | charge pleine en 1 s | charge pleine en 0,7 s |

## Les commandes

| Action | Manette | Clavier joueur 1 | Clavier joueur 2 |
|---|---|---|---|
| Se déplacer | Stick gauche ou croix | Z Q S D | Flèches |
| Sauter (2 fois en l'air) | A | Espace | L |
| Attaque légère | X | F | K |
| Attaque légère visée | stick droit (pichenette) | - | - |
| Attaque lourde (garder pour charger) | Y | R | I |
| Dash (dans la direction du stick) | LB | G | J |
| Courir (maintenir) | Gâchette gauche LT | Shift gauche | Shift droit |
| Bloquer (maintenir) | B | C | U |
| Descendre d'une plateforme | Bas (même en diagonale) | S | Flèche bas |
| Rejouer à la fin | Start ou A | Entrée | Entrée |
| Revenir au menu à la fin | B | Échap | Échap |
| Pause | Start | Échap ou P | Échap ou P |

- Garder le saut appuyé = saut plus haut. Le lâcher tôt = petit saut.
- En l'air, on a droit à un seul dash avant de retoucher le sol. Un dash vers le haut sert de 3e saut.
- **Murs** : en l'air, pousse le stick vers un mur pour t'y coller. Tu glisses doucement vers le bas, et tes 2 sauts et ton dash sont rechargés. Saute pour rebondir dans l'autre sens.
- Le premier qui appuie sur une touche est le joueur 1, le suivant le joueur 2, etc.

## Jouer sur ton téléphone avec une manette Bluetooth

1. Connecte ta manette au téléphone dans les réglages Bluetooth du téléphone.
2. Ouvre le lien du jeu dans Chrome (ou Safari sur iPhone) et tourne le téléphone à l'horizontale.
3. Appuie sur **A** : ta manette devient le joueur 1.

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

Appuie sur **F5**, ou clique sur le triangle ▶ en haut à droite. Une fenêtre s'ouvre sur l'écran « Appuie sur une touche ».
Astuce : ouvre `scenes/main.tscn` et appuie sur **F6** pour aller directement au combat (joueur 1 = Z Q S D ou manette 1, joueur 2 = flèches ou manette 2).
Tu peux jouer au clavier ou brancher une manette. Ferme la fenêtre pour revenir à l'éditeur.

### 5. Modifier le jeu

- **Un personnage** (vitesse, hauteur de saut, dash, attaques, poids…) : double-clique sur `characters/barre.tres`
  dans le panneau « Système de fichiers » en bas à gauche. Ses réglages s'affichent à droite dans l'inspecteur, rangés par groupes
  (Déplacement, Dash, Attaque légère…). Change un chiffre, fais **Ctrl+S**, puis **F5** pour tester.
- **Ajouter un personnage** : clic droit sur `characters/barre.tres` > Dupliquer, donne-lui un nom, change ses réglages
  (son nom et sa courte `description` s'affichent dans le choix du perso), puis ajoute son chemin dans la liste `CHARACTERS`
  de `scripts/game_setup.gd`. Tout suit ses réglages : sa taille, ses sauts, son dash, la longueur et l'épaisseur de ses attaques
  (le dessin suit la zone qui touche), son bouclier, son endurance, et son **poids** (un perso 2 fois plus lourd est
  repoussé 2 fois moins loin par les coups, les chocs et le bouclier, et repousse plus loin les plus légers quand ils se contrent).
  Le poids se **calcule tout seul selon la taille** : laisse `weight` à 0 et change `body_size`, le perso devient plus lourd
  s'il prend plus de place (mets un autre chiffre dans `weight` pour forcer un poids). Le reste (vitesse, sauts…) se règle
  à la main : c'est ce qui donne à chaque perso son caractère.
- **Les règles communes à tous** (bouclier, contre, invincibilité…) : en haut de `scripts/fighter.gd`, chaque règle est une ligne `const` avec une explication.
- **La map** : ouvre `scenes/maps/arene.tscn`. Dans l'arbre à gauche, clique sur `Sol`, `PlateformeMilieu`, `PlateformeHaut`, `MurGauche`, `MurDroit`
  ou une pièce de `ZoneAerienne` / `ZoneDuel`, et déplace-les avec la souris dans la vue du milieu. Attention, chaque plateforme a deux enfants à garder de la même taille :
  `Collision` (la forme qui bloque) et `Visuel` (le rectangle de couleur).
  Les plateformes mobiles (`Ascenseur`, `AscenseurHaut`, `NavetteBasse`, `NavetteHaute`, `NavetteSommet`) se règlent à droite dans l'inspecteur :
  `size` (taille), `travel` (trajet) et `period` (durée d'un aller-retour en secondes).
- **Ajouter une map** : clic droit sur `scenes/maps/arene.tscn` > Dupliquer, change le décor (garde les nœuds `SpawnPoints` et `RespawnPoint`),
  puis ajoute son chemin dans la liste `MAPS` de `scripts/game_setup.gd`. La zone hors de laquelle on tombe se règle dans l'inspecteur (`blast_zone`).
  Les marqueurs de `SpawnPoints` et `RespawnPoint` indiquent les **pieds** du perso : place-les juste au-dessus d'un sol,
  et un grand perso comme un petit apparaîtra posé dessus. Le petit plan du choix de la map se dessine tout seul.
- **Filet de sécurité** : les tests automatiques vérifient chaque perso et chaque map des listes (réglages complets,
  4 points d'apparition dans la zone de jeu, `Collision` et `Visuel` de la même taille, 4 joueurs qui atterrissent bien).
  S'il manque quelque chose, la mise en ligne s'arrête et le jeu en ligne n'est pas cassé.
- **La caméra** : en haut de `scripts/game.gd`, les réglages `CAMERA_...` (marge autour des joueurs, zoom le plus proche et le plus éloigné, vitesse).

## Jouer en ligne avec les copains

1. Dans le menu, choisis **EN LIGNE**, puis **CRÉER UN SALON**. Le jeu affiche un code de 4 lettres (ex. `KBZT`) : donne-le à tes copains.
2. Chaque copain ouvre le jeu sur son ordinateur, choisit **EN LIGNE**, puis **REJOINDRE UN SALON**, et tape le code.
3. Dans le salon, chacun choisit son perso (gauche / droite) et appuie sur A quand il est prêt.
4. Quand tout le monde est prêt, l'hôte (celui qui a créé le salon) appuie sur A, choisit la map et lance la partie.

Un seul joueur par ordinateur, jusqu'à 4. La partie tourne chez l'hôte : **l'hôte doit garder l'onglet du jeu affiché** (si son navigateur passe en arrière-plan, le jeu se fige pour tout le monde). Les copains envoient leurs touches à l'hôte, qui leur renvoie l'image du jeu.

Comment ça marche : le petit serveur des salons (dossier `server/`, sur Cloudflare, gratuit) sert seulement à se retrouver avec le code. Ensuite, chaque navigateur est relié directement à celui de l'hôte (WebRTC). Si la box d'un copain bloque cette connexion directe, le jeu le dit au bout de 15 secondes.

## Prochaines étapes

1. Utiliser le moteur de temps (`scripts/time_engine.gd`) pour d'autres moments forts (ralentis et accélérations).
2. Une deuxième map.
3. Des attaques spéciales avec des combinaisons de touches.
4. Jeu en ligne : un relais pour les box qui bloquent la connexion directe, et rendre les mouvements plus fluides chez les copains.

## Comment le code est organisé

| Fichier | Rôle |
|---|---|
| `scenes/menu.tscn` + `scripts/menu.gd` | Le menu : « Appuie sur une touche », les boutons, le choix du perso et de la map |
| `scripts/pause_menu.gd` | Le menu pause : Reprendre, Restart, Remap, Quitter |
| `scripts/menu_input.gd` + `scripts/ui_kit.gd` | Ce que les deux menus partagent : la lecture des touches et les morceaux d'affichage |
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
| `scripts/input/` | Les commandes de chaque joueur (clavier, manette, ou reçues par le réseau en ligne) |
| `scripts/online/` | Le jeu en ligne : salons avec un code, connexion directe entre navigateurs, envoi des touches et de l'état du jeu |
| `server/` | Le petit serveur des salons (Cloudflare Workers), avec ses tests |
| `tests/` | Un test automatique qui simule des parties et vérifie les règles |
| `.github/workflows/web.yml` | Construit la version web et la publie sur GitHub Pages à chaque modification de `main` |
| `.github/workflows/server.yml` | Teste le serveur des salons (Cloudflare le met en ligne lui-même quand `main` change) |
