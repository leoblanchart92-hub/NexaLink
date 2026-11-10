# Phase 8.3 — audit de l'intégration WireGuard Android

## Périmètre et provenance

NexaLink dépend de `com.wireguard.android:tunnel:1.0.20230706` dans
`android/app/build.gradle`. Le tag public WireGuard Android
[`1.0.20230706`](https://github.com/WireGuard/wireguard-android/tree/58789d6372e8948b87f5c47da7e5f2ad570eb531)
pointe sur le commit `58789d6372e8948b87f5c47da7e5f2ad570eb531`. Ses
[`go.mod`](https://github.com/WireGuard/wireguard-android/blob/58789d6372e8948b87f5c47da7e5f2ad570eb531/tunnel/tools/libwg-go/go.mod)
et [`Makefile`](https://github.com/WireGuard/wireguard-android/blob/58789d6372e8948b87f5c47da7e5f2ad570eb531/tunnel/tools/libwg-go/Makefile)
indiquent wireguard-go `21636207a6756120f56f836b06c086b627f7b911` et Go
1.20.3. Les métadonnées Go de `libwg-go.so` examinées dans l'APK du
[run 42784218344](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42784218344)
sont cohérentes avec ces versions pour les quatre ABI ; elles n'établissent
pas à elles seules l'équivalence de tout le binaire et du code source.

Le [job d'audit de provenance](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42837771479)
a téléchargé l'AAR Maven publié (SHA-256
`df8f5358d3a350d707b5614a493fc3e4dbd0e60a8aae9d9a0cd3fe10d94a2f64`)
et son `sources.jar` (SHA-256
`e123f302157264ae1b67928b56efdb2fb2c1c62a37fa0546632893d24f88a6a6`).
Les quatre fichiers Java audités `GoBackend`, `Backend`, `Tunnel` et
`Statistics` du `sources.jar` sont identiques octet pour octet aux fichiers
correspondants de ce commit public. Un contrôle séparé relève l'empreinte de
l'AAR effectivement résolu par Gradle et désassemble ses classes ; ce contrôle
ne compare que les propriétés rapportées. Un fichier source publié identique,
une empreinte ou une version de dépendance ne sont **pas une reconstruction
reproductible prouvant tous les octets du binaire natif**. La provenance
cryptographique et l'équivalence complète source–binaire restent à établir.

Sources étudiées :

* [`GoBackend.java`](https://github.com/WireGuard/wireguard-android/blob/58789d6372e8948b87f5c47da7e5f2ad570eb531/tunnel/src/main/java/com/wireguard/android/backend/GoBackend.java),
  [`Backend.java`](https://github.com/WireGuard/wireguard-android/blob/58789d6372e8948b87f5c47da7e5f2ad570eb531/tunnel/src/main/java/com/wireguard/android/backend/Backend.java),
  [`Statistics.java`](https://github.com/WireGuard/wireguard-android/blob/58789d6372e8948b87f5c47da7e5f2ad570eb531/tunnel/src/main/java/com/wireguard/android/backend/Statistics.java)
  et [`Tunnel.java`](https://github.com/WireGuard/wireguard-android/blob/58789d6372e8948b87f5c47da7e5f2ad570eb531/tunnel/src/main/java/com/wireguard/android/backend/Tunnel.java).
* Pont [`api-android.go`](https://github.com/WireGuard/wireguard-android/blob/58789d6372e8948b87f5c47da7e5f2ad570eb531/tunnel/tools/libwg-go/api-android.go)
  et moteur exact : [`device.go`](https://github.com/WireGuard/wireguard-go/blob/21636207a6756120f56f836b06c086b627f7b911/device/device.go),
  [`send.go`](https://github.com/WireGuard/wireguard-go/blob/21636207a6756120f56f836b06c086b627f7b911/device/send.go),
  [`receive.go`](https://github.com/WireGuard/wireguard-go/blob/21636207a6756120f56f836b06c086b627f7b911/device/receive.go)
  et [`tun_linux.go`](https://github.com/WireGuard/wireguard-go/blob/21636207a6756120f56f836b06c086b627f7b911/tun/tun_linux.go).

## Contrat et cycle de vie

1. `Backend` expose `getRunningTunnelNames`, `getState`, `getStatistics`,
   `getVersion` et `setState`. `Tunnel.onStateChange` signale `UP` ou `DOWN` ;
   `AlwaysOnCallback` concerne le démarrage Android Always-on, pas un paquet
   ou un handshake. `GuestTunnel` ne transmet pas actuellement son callback
   de changement d'état à une interface produit.
2. Dans la source taguée, `setState(UP)` vérifie le consentement, demande le
   service, attend son instance au plus deux secondes, prépare la configuration
   puis construit le TUN Android avec les adresses et routes des pairs. Après
   `Builder.establish()`, `detachFd()` transfère le FD à `wgTurnOn`. Le pont
   Go crée un TUN non surveillé à partir du FD, construit l'appareil, applique
   la configuration et appelle `device.Up()` ; le `handle` négatif est un
   échec. `UP` signifie que ce chemin de démarrage local a terminé, **pas** que
   les paquets de chaque UID empruntent la route VPN ou que le pair répond.
3. `GoBackend` récupère ensuite les FD des sockets IPv4 et IPv6 par des JNI
   privées et appelle `VpnService.protect(fd)`. Dans la source taguée les deux
   booléens sont ignorés ; aucun résultat n'est exposé par `Backend`. Les
   FD/réflexions utilisés dans certains tests ne sont pas une API stable, ni
   une preuve de protection. `setUnderlyingNetworks(null)` laisse Android
   choisir le réseau sous-jacent ; le chemin Java invité ne fait pas de
   `Network.bindSocket` explicite pour ces sockets. Ne pas confondre les
   sockets externes protégées avec les sockets de sonde destinées au VPN.
4. `NewDevice` démarre notamment le lecteur TUN, les workers de chiffrement,
   déchiffrement et handshake ; l'activation du bind démarre les récepteurs
   réseau. La lecture TUN consulte les `AllowedIPs` et place les paquets en
   attente pour leur pair. La réception filtre et déchiffre, puis la réponse
   est écrite dans le TUN. Ces workers, les erreurs et les points de lecture et
   écriture ne sont pas exposés sous forme de compteurs publics par cet AAR.
5. `getStatistics` interroge la configuration native et renvoie, par pair,
   octets `rx`/`tx` et date du dernier handshake. La source retourne des
   statistiques vides si le tunnel/handle n'est pas courant ou si la requête
   native est nulle, et met des zéros si certaines valeurs sont invalides :
   un zéro isolé ne distingue donc pas toutes les causes. La date est un
   instantané en temps epoch, **pas un callback temps réel** ; l'écho reçu est
   une preuve de bout en bout uniquement pour le paquet et le moment du test.
   Ne jamais journaliser la chaîne brute de configuration native, qui peut
   contenir des clés.
6. `setState(DOWN)` efface les références, appelle `wgTurnOff` puis `stopSelf`
   et signale l'état. Le pont ferme l'éventuel listener UAPI puis `Device.Close`
   ferme le TUN, arrête le bind et attend les éléments suivis par ses waitgroups.
   `stopSelf` ne signifie pas que `onDestroy` a déjà fini ; celui-ci réinitialise
   le futur statique du service et peut aussi arrêter le tunnel propriétaire.
   Dans NexaLink, le bail est gardé jusqu'à la disparition du service observée
   par `ActivityManager`, et conservé en cas de doute ; il est limité au
   processus. Une révocation externe nécessite encore un nettoyage explicite.

Le `VpnService` du backend est l'unique propriétaire du TUN invité. Android
peut exposer un réseau et ses routes avant que toutes les étapes du trajet des
paquets soient fonctionnelles ; le résultat `UP`, `getActiveNetwork`,
`LinkProperties` et `NetworkCallback.onAvailable` ne constituent pas un
accusé de réception de données. Les callbacks sont asynchrones et les lectures
sont propres à l'UID qui les effectue. Les runs 8.2 illustrent précisément
qu'une route visible et même une liaison explicite peuvent précéder un échec
réel ; ils ne prouvent pas pourquoi. Les notifications, l'absence du service,
les snapshots et les FD restent des indices partiels, non des barrières de
synchronisation universelles. Les méthodes de NexaLink sont synchronisées par
objet, mais cela ne démontre pas la sérialisation avec tous les événements
Android externes ; aucune course précise n'est démontrée ici.

## Deux options, sans remplacement dans cette phase

| | A — AAR actuel, API publiques | B — moteur dont les sources sont maîtrisées |
|---|---|---|
| Possibilités | États, échecs de démarrage, statistiques/handshake, observations Android et écho réel | Instrumentation explicite de chaque bord TUN, bind UDP, handshake, déchiffrement, erreurs et fermeture |
| Limites | Pas de compteur de lecture/écriture TUN ni retour `protect`; `UP` et snapshots ne prouvent pas la livraison | Une attribution de cycle à un datagramme chiffré n'est pas automatique ; les compteurs, leurs frais et les pertes de diagnostic doivent être testés |
| Risques | Dépendance binaire et limites d'observabilité ; API privées fragiles | Fork et maintenance upstream, sécurité, licences, ABI/NDK, propriétaire du FD et gestion de fermeture, compatibilité Android, reproductibilité et dérive des versions |
| Runtimes Go | Garde actuelle et processus séparés nécessaires | Un seul runtime Go par processus, ou un processus isolé avec coordination explicite ; ne pas charger deux runtimes Go incompatibles |

**Recommandation :** conserver l'AAR pour l'instant, exploiter d'abord les
observations A sans les confondre avec une garantie de disponibilité, et
prototyper séparément B si le point exact de perte exige les compteurs internes.
Comparer ensuite un build instrumenté à l'AAR officiel et tester isolément
propriété du TUN/FD, retour de `protect`, fermetures, crashs, Android 10/15 et
appareils physiques avant toute migration. Aucun changement de bibliothèque,
de route ou de sécurité n'est justifié par les données actuelles.

L'incident historique SIGSEGV après chargement des deux runtimes Go est une
question distincte. `libwg-go.so` et `libgojni.so` embarquent des versions Go
différentes ; les symboles communs et la chronologie du crash ne démontrent pas
sa cause. La garde conservatrice reste en place ; absence de crash dans une
série ne vaut pas résolution.

## Essais courts de cycle de vie

Les tests appariés Phase 8.2 restent inchangés. Un test séparé observe huit
cycles réels par émulateur : état et service avant, retour du démarrage,
snapshot des FD par réflexion diagnostique uniquement, réseau vu par l'UID de
la sonde, premier écho, snapshot des statistiques, retour d'arrêt, disparition
observée du VPN et bail. Le temps exact de `establish`, d'ouverture des sockets,
le résultat de `protect`, le premier handshake et la première lecture TUN ne
sont pas exposés : ils sont marqués indisponibles ou snapshot, jamais inventés.
Les callbacks sont ceux du processus de la sonde ; l'inspection supplémentaire
peut modifier les timings et les résultats ne sont pas directement équivalents
à ceux du test apparié. Les journaux complets sont conservés dans l'artifact.
Les séries de 100 cycles restent désactivées par défaut.

### Premiers résultats de la phase

Le [run 42837771479](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42837771479)
(teste `30ffc0e029e66ed131420e119709088225e061ae`) est globalement en échec.
L'empreinte SHA-256 de l'AAR effectivement résolu est identique à l'AAR Maven
publié : `df8f5358d3a350d707b5614a493fc3e4dbd0e60a8aae9d9a0cd3fe10d94a2f64`.
Les `libwg-go.so` des quatre ABI sont chacun identiques octet pour octet entre
cet AAR et l'APK de ce run. Le désassemblage du `classes.jar` résolu confirme
**deux appels à `protect(int)` dont le retour est dépilé**. Ce contrôle ciblé,
les fichiers source identiques et les versions Go sont des correspondances
fortes mais ne constituent toujours pas une reconstruction reproductible de
l'ensemble AAR/natif depuis les sources.

| Essai | Android 10 x86_64 | Android 15 x86_64 |
|---|---:|---:|
| Référence appariée, enregistrements | 30/30 | 30/30 |
| Référence, échos implicites / liés | 27/30 / 29/30 | 24/30 / 24/30 |
| Référence, cycles échoués | 4/30 | 12/30 |
| Observation séparée du cycle de vie | 7/8 échos, 1 échec | 8/8 échos |

Dans les cycles appariés échoués, la première sonde échoue puis la seconde
réussit (4/4 et 12/12), indépendamment de la liaison. L'observation séparée
n'est pas équivalente à la référence à cause de ses inspections supplémentaires.
Exemple Android 10, cycle de vie 0 réussi : avant, `DOWN` et service non listé ;
retour `UP` à `247531` ms, deux FD socket observés à `247536` ms, réseau VPN
visible pour la sonde, écho reçu à `247561` ms, snapshot `tx=228 rx=172` avec
handshake positif, puis retour `DOWN`, service non listé et bail libéré. Les FD
après arrêt sont `closed-or-reused` : cette observation ne prouve pas l'absence
de fuite de toutes les ressources. Le résumé de ce run ne contient pas l'exemple
individuel de la sonde échouée, bien qu'il soit conservé dans le JSONL de
l'artifact ; ce n'est pas un succès.

Backend, Go Linux x86_64/ARM64 natif, Flutter, Kotlin et APK réussissent ; les
étapes Android 10/15 échouent. Android 6 passe ses tests de base mais ignore les
tests VPN nécessitant une API plus récente. ARM Android traduit non lancé.
[Provenance](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42837771479/artifacts/13774412106),
[diagnostics Android et désassemblage](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42837771479/artifacts/13775881991),
[APK de développement](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42837771479/artifacts/13773504879).

Le [run 42841600207](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42841600207)
(teste `35e76dba8718c1005cd34b5f7a366fa4c247276c`) est lui aussi en échec :
la référence appariée enregistre 30/30 cycles sur chaque version et échoue sur
7 cycles Android 10 (27/30 implicites, 26/30 liés) et 8 cycles Android 15
(24/30 implicites, 28/30 liés). Dans tous ces cas, la première sonde échoue
et la seconde réussit. L'observation de cycle de vie séparée donne cette fois
8/8 échos et handshakes constatés sur les deux versions : cela ne supprime
pas l'échec 1/8 Android 10 du run précédent et ne valide pas la stabilité.
Backend, provenance, Go Linux x86_64/ARM64, Flutter, Kotlin et APK réussissent ;
Android 6 passe ses tests de base avec exclusions liées à l'API. Les tests ARM
traduits et les séries de 100 cycles ne sont pas lancés. La comparaison de
l'AAR et des quatre bibliothèques natives redonne les mêmes empreintes.
[Provenance](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42841600207/artifacts/13777140655),
[diagnostics](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42841600207/artifacts/13778765505),
[APK de développement](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42841600207/artifacts/13777046849).
