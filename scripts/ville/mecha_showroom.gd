class_name MechaShowroom
extends Node2D
## La vitrine des mechas (étape 4 du plan : leur design). Le même mecha piloté par Barre, Jumb et Jib,
## côte à côte, fait la même pose ; elle change toute seule toutes les POSE_TIME secondes.
## Gauche / droite (ou les flèches) : pose précédente / suivante. Échap ou B : retour au menu.
## Pour l'ouvrir : https://bbstain.github.io/jvtest/?vitrine

const SCENE := "res://scenes/mecha_vitrine.tscn"
const POSE_TIME := 3.0
const POSE_NAMES := ["Repos", "Marche", "Vol", "Tir (rafale)", "Tir lourd (roquette / laser)", "Usure",
	"Arrivée du ciel", "Explosion"]

var mechas: Array[MechaVisual] = []
var pose_index := 0
var _timer := 0.0
var _label: Label

static var _shown := false


## La vitrine est-elle demandée ? (?vitrine dans l'adresse, une seule fois par chargement de la page)
static func requested() -> bool:
	if _shown or not OS.has_feature("web"):
		return false
	_shown = true
	return str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).has('vitrine')")) == "true"


func _ready() -> void:
	var background := ColorRect.new()
	background.color = UiKit.BG_COLOR
	background.position = Vector2(-2000, -1500)
	background.size = Vector2(4000, 3000)
	add_child(background)
	var ground := ColorRect.new()
	ground.color = Color("#3a3d45")
	ground.position = Vector2(-2000, 0)
	ground.size = Vector2(4000, 400)
	add_child(ground)
	for i in GameSetup.CHARACTERS.size():
		var mecha := MechaVisual.new()
		mecha.stats = load(GameSetup.CHARACTERS[i]) as CharacterStats
		mecha.color = Game.PLAYER_COLORS[i]
		mecha.position = Vector2((i - 1) * 540.0, 0.0)
		mecha.heavy_weapon = "laser" if i == 1 else "roquette"
		add_child(mecha)
		mechas.append(mecha)
		var name_label := UiKit.label(mecha.stats.display_name, 26, UiKit.TEXT_DIM)
		name_label.position = mecha.position + Vector2(-60, 30)
		name_label.size = Vector2(120, 40)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(name_label)
	var camera := Camera2D.new()
	camera.position = Vector2(0, -280)
	camera.zoom = Vector2.ONE * 0.7
	add_child(camera)
	camera.make_current()
	var hud := CanvasLayer.new()
	add_child(hud)
	_label = UiKit.label("", 34, UiKit.HIGHLIGHT)
	_label.position = Vector2(0, 30)
	_label.size = Vector2(get_viewport_rect().size.x, 50)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_label)
	var help := UiKit.label("Gauche / droite : autre pose     Échap : menu", 18, UiKit.TEXT_DIM)
	help.position = Vector2(0, get_viewport_rect().size.y - 50)
	help.size = Vector2(get_viewport_rect().size.x, 30)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(help)
	show_pose(0)


## Toutes les mechas prennent la pose n° index (voir POSE_NAMES).
func show_pose(index: int) -> void:
	pose_index = posmod(index, POSE_NAMES.size())
	_timer = 0.0
	_label.text = POSE_NAMES[pose_index]
	for mecha in mechas:
		mecha.set_pose(pose_index as MechaVisual.Pose)
		mecha.aim = -0.35 if pose_index in [MechaVisual.Pose.SHOOT, MechaVisual.Pose.HEAVY] else 0.0
		mecha.wear = 0.0


func _process(delta: float) -> void:
	_timer += delta
	if pose_index == MechaVisual.Pose.WORN:
		for mecha in mechas:
			mecha.wear = clampf(_timer / POSE_TIME, 0.0, 1.0)  # de neuf à presque détruit
	if _timer >= POSE_TIME:
		show_pose(pose_index + 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		show_pose(pose_index + 1)
	elif event.is_action_pressed("ui_left"):
		show_pose(pose_index - 1)
	elif event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file(GameSetup.MENU_SCENE)
