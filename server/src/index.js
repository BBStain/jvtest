// Le petit serveur des salons en ligne.
//
// Il ne fait tourner AUCUNE partie : il aide seulement les joueurs à se retrouver.
//   1. L'hôte ouvre un salon avec un code (ex. "KBZT") : wss://.../salon/KBZT?hote=1
//   2. Les copains rejoignent avec le même code :    wss://.../salon/KBZT
//   3. Le serveur fait passer les messages de connexion (WebRTC) entre eux ; ensuite la
//      partie passe directement d'un navigateur à l'autre, sans le serveur.
//
// Chaque salon est un « Durable Object » Cloudflare : une petite boîte qui garde les
// joueurs connectés à ce code. Les WebSockets « hibernent » quand personne ne parle,
// pour rester largement dans l'offre gratuite.
//
// Messages (JSON) :
//   serveur -> joueur : {"type": "bienvenue", "id": 1, "joueurs": [2, 3]}  (l'hôte a toujours l'id 1)
//                       {"type": "arrivee", "id": 3}  /  {"type": "depart", "id": 3}
//                       {"type": "signal", "de": 2, "data": {...}}
//                       {"type": "erreur", "raison": "code_pris" | "introuvable" | "plein" | ...}
//                       {"type": "ferme"}  (l'hôte est parti : le salon n'existe plus)
//   joueur -> serveur : {"type": "signal", "a": 1, "data": {...}}

import { DurableObject } from "cloudflare:workers";

const MAX_JOUEURS = 4;
const MAX_MESSAGE = 16 * 1024;
const CODE = /^[A-Z]{4}$/;
// Pages autorisées à se connecter (le jeu en ligne et les tests en local).
// Une version du jeu hors navigateur n'envoie pas d'origine : elle est acceptée aussi.
const ORIGINES = [/^https:\/\/bbstain\.github\.io$/, /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/];
// Serveurs publics gratuits qui aident deux navigateurs à se trouver sur internet (STUN).
const ICE = [{ urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] }];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/") {
      return json({ ok: true, jeu: "jvtest" });
    }
    if (url.pathname === "/ice") {
      return json({ iceServers: ICE });
    }
    const match = url.pathname.match(/^\/salon\/([A-Za-z]+)$/);
    if (!match) {
      return new Response("Introuvable", { status: 404 });
    }
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Il faut une connexion WebSocket", { status: 426 });
    }
    const origin = request.headers.get("Origin");
    if (origin && !ORIGINES.some((o) => o.test(origin))) {
      return new Response("Origine refusée", { status: 403 });
    }
    const code = match[1].toUpperCase();
    if (!CODE.test(code)) {
      return new Response("Code de salon invalide", { status: 400 });
    }
    const salon = env.SALONS.get(env.SALONS.idFromName(code));
    return salon.fetch(request);
  },
};

export class Salon extends DurableObject {
  async fetch(request) {
    const hote = new URL(request.url).searchParams.get("hote") === "1";
    const pair = new WebSocketPair();
    const [client, serveur] = Object.values(pair);
    this.ctx.acceptWebSocket(serveur);

    const joueurs = this.joueurs();
    const refus = (raison) => {
      serveur.send(JSON.stringify({ type: "erreur", raison }));
      serveur.close(4000, raison);
      return new Response(null, { status: 101, webSocket: client });
    };
    const aUnHote = joueurs.some((j) => j.id === 1);
    if (hote && aUnHote) return refus("code_pris");
    if (!hote && !aUnHote) return refus("introuvable");
    if (joueurs.length >= MAX_JOUEURS) return refus("plein");

    // L'hôte a l'id 1, les autres le plus petit numéro libre à partir de 2.
    let id = 1;
    if (!hote) {
      id = 2;
      while (joueurs.some((j) => j.id === id)) id++;
    }
    serveur.serializeAttachment({ id });
    serveur.send(JSON.stringify({ type: "bienvenue", id, joueurs: joueurs.map((j) => j.id).sort((a, b) => a - b) }));
    for (const j of joueurs) {
      j.ws.send(JSON.stringify({ type: "arrivee", id }));
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    const moi = ws.deserializeAttachment();
    if (!moi) return;
    if (typeof message !== "string" || message.length > MAX_MESSAGE) {
      ws.send(JSON.stringify({ type: "erreur", raison: "message_invalide" }));
      return;
    }
    let msg;
    try {
      msg = JSON.parse(message);
    } catch {
      ws.send(JSON.stringify({ type: "erreur", raison: "message_invalide" }));
      return;
    }
    if (msg.type === "signal") {
      const cible = this.joueurs().find((j) => j.id === msg.a);
      if (cible) {
        cible.ws.send(JSON.stringify({ type: "signal", de: moi.id, data: msg.data }));
      }
    }
  }

  async webSocketClose(ws, code, raison) {
    this.depart(ws);
    try {
      ws.close(code === 1005 ? 1000 : code, raison);
    } catch {
      // déjà fermé
    }
  }

  async webSocketError(ws) {
    this.depart(ws);
  }

  // Un joueur s'en va. Si c'est l'hôte, le salon ferme pour tout le monde.
  depart(ws) {
    const moi = ws.deserializeAttachment();
    if (!moi) return;
    ws.serializeAttachment(null);
    for (const j of this.joueurs()) {
      if (moi.id === 1) {
        j.ws.send(JSON.stringify({ type: "ferme" }));
        j.ws.serializeAttachment(null);
        j.ws.close(1000, "ferme");
      } else {
        j.ws.send(JSON.stringify({ type: "depart", id: moi.id }));
      }
    }
  }

  // Les joueurs encore dans le salon : {id, ws}.
  joueurs() {
    const liste = [];
    for (const ws of this.ctx.getWebSockets()) {
      const info = ws.deserializeAttachment();
      if (info) liste.push({ id: info.id, ws });
    }
    return liste;
  }
}

function json(data) {
  return new Response(JSON.stringify(data), {
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
