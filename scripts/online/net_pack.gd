class_name NetPack
extends RefCounted
## Jeu en ligne : range l'état d'un objet (une liste de variables) en un paquet plus petit.
##
## Godot envoie chaque nombre sur 12 octets (et chaque oui/non sur 8). Ici, tous les nombres,
## oui/non et Vector2 sont mis bout à bout dans un PackedFloat32Array (4 octets par nombre),
## et le reste (les textes) à part. Un joueur passe ainsi d'environ 560 à 330 octets par frame :
## l'état du jeu tient dans un seul paquet réseau, il arrive plus vite et se perd moins.
##
## L'hôte et le copain ont le même code : ils savent tous les deux, d'après le type déclaré de
## chaque variable, combien de nombres elle prend. Une variable sans type va avec les textes.

static var _layouts := {}  ## script -> type de chaque variable (calculé une fois)


static func pack(target: Object, vars: Array) -> Array:
	var numbers := PackedFloat32Array()
	var others := []
	var types := _types(target, vars)
	for i in vars.size():
		var value = target.get(vars[i])
		match types[i]:
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
				numbers.append(float(value))
			TYPE_VECTOR2:
				numbers.append(value.x)
				numbers.append(value.y)
			_:
				others.append(value)
	return [numbers, others]


static func unpack(target: Object, vars: Array, data: Array) -> void:
	if data.size() < 2 or not data[0] is PackedFloat32Array or not data[1] is Array:
		return
	var numbers: PackedFloat32Array = data[0]
	var others: Array = data[1]
	var types := _types(target, vars)
	var n := 0
	var o := 0
	for i in vars.size():
		match types[i]:
			TYPE_BOOL:
				if n >= numbers.size():
					return
				target.set(vars[i], numbers[n] != 0.0)
				n += 1
			TYPE_INT:
				if n >= numbers.size():
					return
				target.set(vars[i], roundi(numbers[n]))
				n += 1
			TYPE_FLOAT:
				if n >= numbers.size():
					return
				target.set(vars[i], numbers[n])
				n += 1
			TYPE_VECTOR2:
				if n + 1 >= numbers.size():
					return
				target.set(vars[i], Vector2(numbers[n], numbers[n + 1]))
				n += 2
			_:
				if o >= others.size():
					return
				target.set(vars[i], others[o])
				o += 1


static func _types(target: Object, vars: Array) -> Array:
	var key = target.get_script()
	if _layouts.has(key):
		return _layouts[key]
	var declared := {}
	for p in target.get_property_list():
		declared[p.name] = p.type
	var types := []
	for v in vars:
		types.append(declared.get(v, TYPE_NIL))
	_layouts[key] = types
	return types
