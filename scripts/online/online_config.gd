class_name OnlineConfig
extends RefCounted
## Où se trouve le serveur des salons (dossier server/, mis en ligne sur Cloudflare).
## Dans le navigateur, on peut en essayer un autre avec l'adresse du jeu :
##   https://bbstain.github.io/jvtest/?serveur=ws://127.0.0.1:8787

const SERVER_URL := "wss://jvtest-salons.CHANGE_ME.workers.dev"

## Serveurs publics gratuits qui aident deux navigateurs à se trouver sur internet (STUN).
const ICE_SERVERS := [{"urls": ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"]}]


static func server_url() -> String:
	if OS.has_feature("web"):
		var override = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('serveur') || ''")
		if override is String and override != "":
			return override
	return SERVER_URL
