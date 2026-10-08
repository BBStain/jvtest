// Tests du serveur des salons : on le lance en local (comme sur Cloudflare) et on
// joue le rôle de l'hôte et des copains avec de vraies connexions WebSocket.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { unstable_startWorker } from "wrangler";

let worker;
let base;

before(async () => {
  worker = await unstable_startWorker({ config: "wrangler.toml", dev: { server: { port: 0 }, inspector: false } });
  const url = await worker.url;
  base = url.href.replace(/^http/, "ws").replace(/\/$/, "");
});

after(async () => {
  await worker?.dispose();
});

// Ouvre une connexion et range les messages reçus dans une file.
function connecter(chemin, origin) {
  const ws = new WebSocket(base + chemin, origin ? { headers: { Origin: origin } } : undefined);
  const recus = [];
  const attente = [];
  ws.binaryType = "arraybuffer";
  ws.addEventListener("message", (e) => {
    const msg = typeof e.data === "string" ? JSON.parse(e.data) : Array.from(new Uint8Array(e.data));
    const w = attente.shift();
    if (w) w(msg);
    else recus.push(msg);
  });
  const ouvert = new Promise((ok, ko) => {
    ws.addEventListener("open", ok);
    ws.addEventListener("error", ko);
  });
  return {
    ws,
    ouvert,
    envoyer: (m) => ws.send(JSON.stringify(m)),
    envoyerOctets: (octets) => ws.send(new Uint8Array(octets)),
    suivant: () =>
      recus.length
        ? Promise.resolve(recus.shift())
        : new Promise((ok, ko) => {
            const t = setTimeout(() => ko(new Error("aucun message")), 5000);
            attente.push((m) => {
              clearTimeout(t);
              ok(m);
            });
          }),
    fermer: () => ws.close(),
  };
}

test("le serveur répond", async () => {
  const r = await fetch(base.replace(/^ws/, "http") + "/");
  assert.equal((await r.json()).ok, true);
  const ice = await (await fetch(base.replace(/^ws/, "http") + "/ice")).json();
  assert.ok(ice.iceServers.length > 0);
});

test("l'hôte crée un salon, les copains le rejoignent et se parlent", async () => {
  const hote = connecter("/salon/ABCD?hote=1");
  assert.deepEqual(await hote.suivant(), { type: "bienvenue", id: 1, joueurs: [] });

  const j2 = connecter("/salon/abcd"); // le code marche aussi en minuscules
  assert.deepEqual(await j2.suivant(), { type: "bienvenue", id: 2, joueurs: [1] });
  assert.deepEqual(await hote.suivant(), { type: "arrivee", id: 2 });

  const j3 = connecter("/salon/ABCD");
  assert.deepEqual(await j3.suivant(), { type: "bienvenue", id: 3, joueurs: [1, 2] });
  await hote.suivant();
  await j2.suivant();

  // Les messages de connexion passent d'un joueur à l'autre
  j2.envoyer({ type: "signal", a: 1, data: { offre: "sdp-de-j2" } });
  assert.deepEqual(await hote.suivant(), { type: "signal", de: 2, data: { offre: "sdp-de-j2" } });
  hote.envoyer({ type: "signal", a: 3, data: { reponse: "sdp-hote" } });
  assert.deepEqual(await j3.suivant(), { type: "signal", de: 1, data: { reponse: "sdp-hote" } });

  // J2 part : les autres sont prévenus, sa place (id 2) se libère
  j2.fermer();
  assert.deepEqual(await hote.suivant(), { type: "depart", id: 2 });
  assert.deepEqual(await j3.suivant(), { type: "depart", id: 2 });
  const j2bis = connecter("/salon/ABCD");
  assert.deepEqual(await j2bis.suivant(), { type: "bienvenue", id: 2, joueurs: [1, 3] });
  await hote.suivant();
  await j3.suivant();

  // L'hôte part : le salon ferme pour tout le monde
  hote.fermer();
  assert.deepEqual(await j3.suivant(), { type: "ferme" });
  assert.deepEqual(await j2bis.suivant(), { type: "ferme" });
});

test("le relais fait passer les paquets du jeu quand la connexion directe ne marche pas", async () => {
  const hote = connecter("/salon/RLAI?hote=1");
  await hote.suivant();
  const j2 = connecter("/salon/RLAI");
  await j2.suivant();
  await hote.suivant();
  const j3 = connecter("/salon/RLAI");
  await j3.suivant();
  await hote.suivant();
  await j2.suivant();

  // J2 envoie à l'hôte : seul l'hôte le reçoit, avec le numéro de J2 devant
  j2.envoyerOctets([1, 10, 20, 30]);
  assert.deepEqual(await hote.suivant(), [2, 10, 20, 30]);
  // L'hôte envoie à tout le monde (0) : J2 et J3 le reçoivent, pas lui
  hote.envoyerOctets([0, 7, 8]);
  assert.deepEqual(await j2.suivant(), [1, 7, 8]);
  assert.deepEqual(await j3.suivant(), [1, 7, 8]);
  // L'hôte envoie à J3 seulement
  hote.envoyerOctets([3, 9]);
  assert.deepEqual(await j3.suivant(), [1, 9]);
  j2.envoyerOctets([1, 5]);
  assert.deepEqual(await hote.suivant(), [2, 5]);  // J2 n'a pas reçu le paquet pour J3 : rien d'autre en file
  assert.equal((await Promise.race([j2.suivant().catch(() => "rien"), new Promise((ok) => setTimeout(() => ok("rien"), 300))])), "rien");
  hote.fermer();
});

test("code déjà pris, salon introuvable, salon plein", async () => {
  const hote = connecter("/salon/QWER?hote=1");
  await hote.suivant();
  const autreHote = connecter("/salon/QWER?hote=1");
  assert.deepEqual(await autreHote.suivant(), { type: "erreur", raison: "code_pris" });

  const perdu = connecter("/salon/ZZZZ");
  assert.deepEqual(await perdu.suivant(), { type: "erreur", raison: "introuvable" });

  const copains = [];
  for (let i = 0; i < 3; i++) {
    const c = connecter("/salon/QWER");
    await c.suivant();
    copains.push(c);
  }
  const cinquieme = connecter("/salon/QWER");
  assert.deepEqual(await cinquieme.suivant(), { type: "erreur", raison: "plein" });
  hote.fermer();
  for (const c of copains) {
    let m = await c.suivant();
    while (m.type === "arrivee") m = await c.suivant();
    assert.equal(m.type, "ferme");
  }
});

// Demande une connexion WebSocket « à la main » et renvoie le code de réponse (101 = accepté).
function statutConnexion(chemin, origin) {
  const url = new URL(base.replace(/^ws/, "http") + chemin);
  return new Promise((ok, ko) => {
    const headers = { Connection: "Upgrade", Upgrade: "websocket", "Sec-WebSocket-Version": "13",
      "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==" };
    if (origin) headers.Origin = origin;
    const req = http.get(url, { headers });
    req.on("response", (r) => { r.resume(); ok(r.statusCode); });
    req.on("upgrade", (r, socket) => { socket.destroy(); ok(r.statusCode); });
    req.on("error", ko);
  });
}

test("une page d'un autre site est refusée, un code invalide aussi", async () => {
  assert.equal(await statutConnexion("/salon/ABCD?hote=1", "https://pas-le-jeu.example"), 403);
  assert.equal(await statutConnexion("/salon/AB?hote=1"), 400);
  assert.equal(await statutConnexion("/salon/WXYZ?hote=1", "https://bbstain.github.io"), 101);
});
