# Étude du moteur réseau NexaLink

> Les sections des phases précédentes sont historiques ; le résultat et les limites actuels figurent dans la section Phase 8 en fin de document.

## Actualisation phase 4

Le code `gateway/mobile` produit un AAR gomobile incluant le moteur Go, WireGuard et gVisor. Un adaptateur Kotlin reçoit un `VpnService` et un réseau sélectionné ; son callback protège les descripteurs et tente de les lier au réseau cellulaire. Le démarrage exige ce callback ; il refuse une erreur plutôt que d'employer le réseau par défaut. Le processus de build et les appels JNI sont testés, mais pas encore le scénario réseau Android réel : un test utilise un callback factice permissif sur émulateur uniquement pour vérifier le démarrage et l'arrêt locaux, et un autre vérifie que le refus du callback empêche le démarrage. Aucun test ne prouve le fonctionnement de `VpnService.protect` ou de `Network.bindSocket` sur un réseau mobile physique.

La méthode Flutter/Kotlin exposée ne fait qu'identifier la version du runtime Go chargé. Elle ne démarre aucun moteur. Il n'y a toujours pas de service propriétaire instanciant l'adaptateur, pas de surveillance de perte cellulaire ni de révocation effective, et pas de protocole d'échange/authentification de clés associé au QR. Le mode invité n'est pas relié à une configuration négociée. Ne pas interpréter un état local WireGuard « démarré » ou un handshake comme une preuve d'accès à Internet. Aucun bouton ne démarre le partage.


## Actualisation phase 3

Le répertoire `gateway/` contient désormais un prototype Go séparé qui relie un TUN en mémoire `wireguard-go` à la pile gVisor via le composant `core` du projet tun2socks. Il ne crée pas de pile TCP/IP maison. Un test CI relie deux vrais pairs WireGuard en UDP local et fait traverser à leurs paquets des flux TCP, UDP et DNS vers des serveurs de test locaux, puis renvoie les réponses. Le dialer de test redirige explicitement l'adresse de destination synthétique vers ces serveurs locaux ; aucune sortie Internet ni connexion mobile n'est testée.

La passerelle est limitée à un seul invité IPv4, valide la source des paquets, filtre les fragments et les protocoles autres que TCP/UDP, borne le nombre de flux et ferme les sockets au moment de la fermeture de la passerelle. WireGuard vérifie les clés du pair configuré ; le prototype ne réalise pas encore l'authentification d'identité, l'échange des clés, la révocation par invité ni l'isolation multi-invité. La politique d'adresses est une ébauche à auditer. Le pont JNI transmet les demandes de protection et de liaison des sockets au Kotlin ; son utilisation effective par un service Android autorisé, la gestion de perte de réseau et la validation en conditions réelles restent à développer. Il est impossible d'affirmer que la sortie cellulaire est forcée avant cette intégration et ses tests. L'APK compile désormais le pont et le prototype, mais le partage n'est pas activable.

Le test unitaire Kotlin vérifie uniquement la logique de sélection des capacités ; il ne teste pas `ConnectivityManager`, `Network.bindSocket` ni un réseau mobile réel. Le texte ci-dessous constitue l'étude initiale ; ses sections « à implémenter » restent valables pour l'intégration Android, même si certains éléments existent désormais en prototype local.

## Comparaison des solutions

- **wireguard-go** : authentifie/chiffre les datagrammes et s'adapte à un TUN en mémoire ; ne fait pas le NAT des connexions Internet.
- **gVisor/netstack via tun2socks** : termine TCP/UDP en espace utilisateur et restitue les paquets de réponse ; ne fournit pas par lui-même un réseau cellulaire Android.
- **tun2socks** : apporte l'interception de flux gVisor ; un proxy SOCKS distant n'est pas requis ici, car le prototype ouvre des sockets via un dialer injecté. Sur Android, ce dialer devra utiliser les primitives natives existantes et échouer si le réseau mobile disparaît.
- **Sockets Android liés à Network** : candidats pour la sortie mobile, mais ils ne traitent pas à eux seuls des paquets IP. Leur intégration au moteur Go et leur protection contre la boucle VPN restent à construire.


## État vérifiable

L'interface Flutter et l'API d'association existantes sont préservées. Le serveur d'association n'est ni un serveur WireGuard, ni un relais. La dépendance officielle `com.wireguard.android:tunnel:1.0.20230706` est intégrée ; les classes natives `GuestConfig` et `GuestTunnel` préparent un client via `GoBackend`, mais ne sont **pas raccordées à Flutter** et n'ont pas été exécutées sur Android. Aucun échange de clé ni aucune authentification de pair ne sont en place. Il n'y a ni tunnel activable, ni passerelle Android, ni relais, ni trafic Internet partagé dans l'application actuelle.

La bibliothèque officielle fournit un backend WireGuard en espace utilisateur sans root, reposant sur `VpnService`, et son service est déclaré par le manifeste de son AAR. Le code de cette version appelle `VpnService.prepare`, crée l'interface et protège les sockets WireGuard. Sa méthode `setState(UP)` indique seulement la création du tunnel local : elle ne prouve ni handshake, ni transfert, ni sortie Internet. Son implémentation indique aussi le VPN non mesuré (`setMetered(false)` sur Android Q+) et ne vérifie pas les retours de `protect` : ces points doivent être étudiés avant usage réel avec un forfait mobile. Notre adaptateur attend l'accord Android, travaille sur un thread de fond et n'est pas exposé à l'utilisateur. Le profil client construit utilise un peer, route IPv4 `0.0.0.0/0`, DNS IPv4 numérique, MTU 1280 et keepalive 25 secondes ; ce sont des paramètres de départ à tester, non des preuves de connectivité. Le client n'implémente pas IPv6 ; il faudra tester sur appareil qu'aucun trafic IPv6 ne contourne le VPN, y compris au démarrage, après arrêt et en cas de panne. Le kill switch Android « VPN permanent / bloquer sans VPN » est un réglage distinct et ne peut pas être promis par la construction du profil.

`CellularEgress` est un début d'interface réseau natif : il sélectionne un réseau cellulaire existant validé (sans basculer sur Wi-Fi) et peut créer des sockets TCP/UDP protégés et liés à ce réseau, en échouant plutôt qu'en ignorant un échec de protection. Il ne démarre pas le réseau mobile et ne transfère aucun paquet. Un réseau peut disparaître aussitôt après sélection ; les appels et la gestion des changements réseau doivent encore être intégrés et testés sur des téléphones. Le `VpnService` requis par la méthode de protection doit être le service actif et autorisé : ce n'est pas encore connecté au backend WireGuard ni à une passerelle.

## Analyse Android et chemin du trafic envisagé

Android ne garantit pas à une application ordinaire le droit d'activer `ip_forward`, d'installer des règles iptables/nftables ou de faire du NAT noyau entre une interface VPN et l'interface mobile. Toute solution fondée sur ces actions exigerait des privilèges supplémentaires/root et n'est pas acceptable par défaut. `VpnService` expose un TUN pour le trafic local, pas une API de routeur universel. Sur le propriétaire, injecter un paquet déchiffré destiné à Internet dans le TUN standard de `GoBackend` ne suffit pas : le noyau ne va pas nécessairement le router vers le réseau mobile. De plus, Android n'autorise généralement qu'un VPN actif par utilisateur/profil : ne pas prévoir deux `VpnService` indépendants en parallèle.

Architecture candidate **à implémenter et valider**, sans root :

1. L'invité utilise un vrai `VpnService` WireGuard ; il envoie les paquets IPv4, y compris les requêtes DNS, à la clé publique authentifiée du propriétaire. Le transport UDP chiffré passe en direct si les NAT le permettent, sinon par un relais adapté. Les sockets de transport doivent être protégés du VPN pour éviter les boucles.
2. Sur le propriétaire, un moteur WireGuard en espace utilisateur avec **TUN personnalisé** reçoit et authentifie les datagrammes puis transmet les paquets IP déchiffrés directement à une pile réseau utilisateur (par exemple gVisor/netstack, sous réserve de vérification de compatibilité Android et licences). Le `GoBackend` Android standard ne donne pas ce chemin de paquets à l'application : intégrer seulement son AAR ne résout pas cette étape. Il faut construire/adapter un moteur natif distinct et sa liaison JNI, sans supposer une interface TUN accessible du dehors.
3. Une pile avec interception TCP/UDP et prise en charge de destinations arbitraires (mode promiscuous/spoofing, si disponible et vérifié) termine les flux reçus. Pour chaque flux TCP, la passerelle ouvre une connexion TCP distincte à la destination via un socket Android protégé et lié à un réseau cellulaire choisi ; elle copie les données dans les deux sens et gère fermeture, demi-fermeture, délais et contre-pression. Pour UDP, elle maintient des associations par flux avec expiration, protège/lie les sockets, limite les ressources et renvoie les datagrammes à la pile. C'est du proxy/NAT en espace utilisateur, pas de l'IP forwarding noyau ; une prise en charge TCP et UDP correcte reste à construire et tester. Les paquets IP de réponse sont réémis vers le client par le moteur WireGuard.
4. Le serveur DNS configuré chez l'invité doit être joignable à travers cette même passerelle, en UDP **et TCP** ; pas de résolution locale cachée ni de fuite DNS. Le propriétaire doit vérifier que le trafic sort par le réseau cellulaire, pas simplement par le réseau par défaut. Après une perte du réseau mobile : fermer les sockets et arrêter/refuser les nouveaux flux, sans bascule silencieuse Wi-Fi. Les destinations locales, bouclage, lien local, multicast et adresses internes doivent être filtrées pour éviter d'exposer le téléphone propriétaire et son réseau ; une politique explicite est nécessaire.
5. Le premier jalon sera IPv4 seulement, avec IPv6 explicitement bloqué et testé sur appareil ; puis ajouter IPv6, ICMP/PMTU, fragmentation, DNS64/NAT64, gestion de MTU et ICMP d'erreur ou documenter les protocoles non pris en charge. Une pile TCP/UDP ne prend pas automatiquement en charge tous les protocoles IP. Pas de garantie universelle de fonctionnement sur tous les opérateurs ou appareils.

Le téléphone propriétaire paiera le trafic sortant ; limitations du forfait et restrictions de l'opérateur peuvent s'appliquer. Le routage via la connexion mobile du propriétaire, l'adresse IP de sortie et la consommation doivent être vérifiés empiriquement, non déduits de l'état du tunnel. L'application doit afficher un consentement explicite et un indicateur clair ; pas d'inspection ni de journalisation des activités invitées.

## NAT mobile et relais

Un point public atteignable n'est pas toujours nécessaire : un tunnel direct peut fonctionner avec des endpoints atteignables ou du hole punching et des keepalives. Mais CGNAT, NAT symétrique, filtrage UDP et changements d'adresse rendent le direct non fiable ; un **relais public est donc nécessaire pour couvrir ces cas**, sans garantir les réseaux qui bloquent l'UDP. La simple API HTTPS d'association ne relaie rien.

Deux stratégies distinctes :

- Un serveur WireGuard public de type hub route les paquets entre pairs, mais il termine les tunnels et peut voir leurs paquets internes ; pour obtenir un chiffrement de bout en bout invité–propriétaire, il faut une couche interne séparée et concevoir soigneusement son intégration Android (un seul VPN système), pas affirmer qu'un hub suffit.
- Un relais de datagrammes dédié pourrait transporter le WireGuard de bout en bout opaque. Il devra authentifier l'enregistrement de chaque endpoint, protéger contre usurpation, rejeu, amplification et abus, limiter les débits, expirer les associations et permettre le changement d'adresse. Les clients et le relais doivent implémenter le même protocole de transport : WireGuard standard ne parle pas spontanément un protocole de relais encapsulé. Aucun tel relais n'est encore implémenté ou hébergé.

Il faudra héberger l'API HTTPS d'association, ainsi qu'un service public de signalisation et, pour le scénario de secours, un relais joignable publiquement avec quotas et supervision. Les clés privées restent sur les téléphones. Le QR existant contient un secret d'invitation, pas une clé WireGuard vérifiée ; un échange de clés publiques lié au consentement, une vérification d'identité de bout en bout (par exemple comparaison explicite d'un code) et la révocation effective par suppression des pairs sont indispensables. Un serveur d'association compromis ne doit pas pouvoir substituer une clé en silence.

## Critères minimaux de validation ultérieure

- Tests natifs : configuration, autorisation/refus Android, vrais handshake et paquets, arrêt/révocation, absence de fuite et cycle de vie du service.
- Pile propriétaire : tests unitaires + intégration TCP, UDP, DNS UDP/TCP, NAT, délais, limites de ressources, perte réseau et retour, politique de destinations, IPv6/ICMP/MTU.
- Deux téléphones physiques sur réseaux mobiles différents, puis scénarios CGNAT et relais, tests de l'IP de sortie du propriétaire et de la facturation ; retrait du consentement et révocation pendant un flux, sans sortie par Wi-Fi ni fuite DNS/IPv6.
- Revue sécurité du protocole, durcissement du backend, gestion d'identité et clés, tests d'abus et signature de production. Un APK de CI est un artifact de développement, pas une validation sur appareil.

## Références primaires

- [Bibliothèque WireGuard Android et instructions d'intégration](https://github.com/WireGuard/wireguard-android/tree/1.0.20230706)
- [Implémentation GoBackend, version utilisée](https://github.com/WireGuard/wireguard-android/blob/1.0.20230706/tunnel/src/main/java/com/wireguard/android/backend/GoBackend.java)
- [Android VpnService](https://developer.android.com/reference/android/net/VpnService), [VPN Android](https://developer.android.com/develop/connectivity/vpn) et [Network.bindSocket](https://developer.android.com/reference/android/net/Network#bindSocket(java.net.Socket))
- [WireGuard Go TUN](https://github.com/WireGuard/wireguard-go/tree/master/tun) et [gVisor netstack](https://github.com/google/gvisor/tree/master/pkg/tcpip/stack) : pistes à valider, pas des dépendances installées ou une preuve de fonctionnement.

### Instabilité du moteur Android à corriger

Les tests répétés sur l'émulateur Android x86_64 ont détecté un plantage
intermittent du processus lors du démarrage/arrêt local du moteur : le runtime
Go signale `bulkBarrierPreWrite: unaligned arguments`. Un passage réussi ne
valide donc pas ce chemin. La cause exacte reste à isoler, puis à corriger et à
retester, notamment sur les autres architectures. Le moteur reste inaccessible
aux boutons de l'application et ne doit pas être activé pour le partage.

### Piste de correction du plantage cgo

Le plantage reproduit sous Go 1.23.10 présente le même message que le défaut
officiel [golang/go#46893](https://github.com/golang/go/issues/46893) : la
structure d'arguments créée par cgo pour les appels exportés peut être mal
alignée, et le ramasse-miettes Go peut terminer le processus. La correction cgo
est incluse dans Go 1.26. La CI utilise désormais Go 1.26.10 pour vérifier cette
piste. La concordance du message seule ne prouve pas que tous les plantages ont
cette cause ; les tests répétés et la compatibilité des dépendances restent à
valider. Le chargement/déchargement répété d'une bibliothèque native dans le
même processus Android n'est pas pris en charge par cette API : les tests
créent des objets moteur indépendants, sans prétendre décharger la bibliothèque.

### Couverture de stabilisation et limites

La CI exécute trois fois une suite comprenant 100 créations/démarrages/arrêts
de moteurs par émulateur, des appels concurrents, le double démarrage, une
configuration invalide, un arrêt demandé pendant un démarrage et un contrôle
du nombre de descripteurs. Les tests utilisent un callback permissif de test,
pas une protection VPN. Un test Go distinct ferme un flux TCP actif local.
Les émulateurs configurés sont Android 6 x86, Android 10 x86_64 et Android 15
x86_64 ; ils ne remplacent pas des essais sur téléphones ARM. Les quatre ABI
Go sont contrôlées dans l'AAR, mais la présence d'une bibliothèque n'est pas
une preuve de son fonctionnement sur cette architecture. La perte réelle du
réseau, les interruptions de service Android et les cycles complets
Flutter–Kotlin–Go ne peuvent pas encore être validés : aucun service ni
commande Flutter ne démarre le moteur. Les tests de mémoire restent partiels.

## Préparation Android — rôles et cycle de vie

Le propriétaire et l'invité restent séparés. Le nouveau contrôleur propriétaire
est un composant interne pour un futur `VpnService` autorisé : il sérialise les
appels au moteur sur un thread de travail, rejette le double démarrage et, sur
notification de perte réseau, met l'arrêt en attente et interdit de réutiliser
ce contrôleur. Un nouveau réseau exige une nouvelle sélection et un nouveau
contrôleur ; aucun basculement vers le Wi-Fi n'est implémenté. Son état
`RUNNING_LOCAL` ne prouve ni handshake ni Internet. La destruction attend
l'arrêt dans le worker avant de publier `DESTROYED`. Si un callback natif est
bloqué, l'arrêt ne peut toujours pas l'interrompre immédiatement. Les tests
unitaires du contrôleur utilisent un moteur de test. Un test instrumenté associe
également le contrôleur au vrai moteur Go et déclenche une notification de perte
artificielle : il passe sur les émulateurs x86/x86_64 du run ci-dessous. Ces
résultats ne prouvent pas le cycle réel d'un service Android, une perte réseau
réelle ou l'absence de fuite.

Le service propriétaire est enregistré mais n'est pas relié aux commandes
Flutter et aucun parcours produit ne prépare sa session. Le contrôleur précédent
reste distinct du cycle du nouveau service. L'invité conserve l'adaptateur `GuestTunnel`
existant et le backend `GoBackend` de WireGuard : il faut encore obtenir le
consentement Android, un profil authentifié, et valider son cycle de vie réel.
Le QR n'a pas été modifié ; il ne doit jamais contenir de clé privée. L'échange
authentifié des clés publiques, la vérification de l'identité, la révocation
réelle et l'intégration des services restent à concevoir et tester avant toute
activation. Aucun de ces composants ne permet actuellement de partager Internet.

### Tentative ARM par traduction sur émulateur x86

Le run [42226592497](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42226592497)
a exécuté une APK limitée à ARM64 sur Android 15 x86_64 via la traduction ARM.
Le processus a planté avec `SIGILL` dans `internal/cpu.getMIDR.abi0` au démarrage
Go ; la trace indique explicitement une architecture invitée arm64 traduite.
Cela ne permet pas d'attribuer le problème à un téléphone ARM physique ni de
valider ARM64. La même image Android 15 est 64 bits et ne propose pas de cible
compatible pour l'APK ARM 32 bits. Dans le run
[42229017826](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42229017826),
une seconde tentative avec une APK limitée à armeabi-v7a sur Android 11 x86 a
planté avec `SIGSEGV` (`SEGV_ACCERR` ; le rapport suggère un débordement de
pile, sans le démontrer). Le programme n'a pas confirmé son architecture Go :
ni l'exécution correcte d'ARM 32 bits, ni son cycle JNI ne sont validés. Ce run
est globalement en échec sur les deux essais ARM ; les autres étapes, dont les
JNI x86/x86_64, ont réussi. Les diagnostics sont conservés dans l'artefact du
run. La cause des deux plantages reste à établir, et des tests sur CPU ARM
physique sont indispensables.


## Phase 7 — service Android expérimental

`OwnerVpnService` est un vrai service Android non exporté, protégé par
`BIND_VPN_SERVICE`, non persistant (`START_NOT_STICKY`), avec notification
foreground et exclusion du mode always-on. Une session interne à usage unique
reste sans appelant produit : la configuration ne passe ni dans une Intent ni
par Flutter. Sans session, consentement VPN ou réseau cellulaire validé, il
s'arrête. En cas de révocation, perte ou invalidation des capacités du réseau
cellulaire, il ferme son interface, désinscrit son callback et met l'arrêt du
moteur en file. Le verrou de rôle n'est libéré qu'après l'arrêt du moteur.
Un callback natif bloqué peut encore retarder cet arrêt. Les clés sont des
`String` en mémoire : l'effacement cryptographique n'est pas garanti.

**Deux TUN différents, jamais deux VPN concurrents intentionnellement :**

- Côté propriétaire, le service crée une interface Android de contrôle sans
  route par défaut. Elle ne sert pas à alimenter gVisor et n'est pas un relais
  de paquets Android. Les datagrammes WireGuard arrivent sur une socket UDP
  protégée et liée au réseau cellulaire. Après authentification WireGuard, le
  TUN **en mémoire** du moteur transmet les IP déchiffrées à gVisor ; les
  réponses suivent le trajet inverse et sont rechiffrées par WireGuard.
- Côté invité, le service `GoBackend.VpnService` de WireGuard crée et possède
  le TUN Android et transmet son descripteur au moteur WireGuard du client.
  Les paquets sélectionnés par les routes du profil partent chiffrés vers le
  propriétaire ; les réponses déchiffrées retournent dans ce même TUN. Il ne
  faut surtout pas connecter le TUN Android propriétaire directement à gVisor,
  ce qui contournerait l'authentification de l'invité.

Un verrou de rôle interne empêche les adaptateurs NexaLink propriétaire et
invité d'établir intentionnellement deux VPN concurrents dans le même processus ;
Android peut toujours révoquer la préparation si un autre VPN prend la main.
Ce verrou ne remplace pas les garanties système ou une validation multi-processus.
La version actuelle de GoBackend protège les sockets invité mais ne contrôle pas
les retours de `protect` ; ce point exige une revue et des tests avant activation.

Les essais automatisés invités utilisent un profil limité à une route de test,
un récepteur UDP sur loopback, un paquet de test et une autorisation accordée
par app-op de l'émulateur. Ils ne valident ni le dialogue de consentement
utilisateur, ni un handshake complet, ni un accès Internet. Les téléphones physiques, la perte
cellulaire réelle, la sélection et protection des sockets propriétaires restent
à tester. Aucune négociation authentifiée des clés ni révocation sécurisée avec
effacement des clés ne sont implémentées ; le QR reste inchangé.

La CI exécute aussi les tests Go sur un runner Linux ARM64 natif et vérifie
`uname -m` et `GOARCH`. Ce résultat, s'il passe, ne valide pas l'AAR Android,
JNI, ARM32 ni un téléphone ARM. Les essais de traduction Android connus en
échec sont conservés en diagnostic optionnel, pas relancés par défaut ; les
plantages historiques restent documentés ci-dessus. La pile ARM64 indique
`internal/cpu.getMIDR.abi0`, une instruction de lecture d'identification CPU
durant l'initialisation Go sous traduction ; une incompatibilité de traduction
est plausible, mais les traces ne permettent pas d'exclure Go ou une autre cause.
La pile ARM32 est insuffisante pour attribuer le `SIGSEGV` au traducteur,
à gomobile ou au moteur. Aucun correctif ARM n'est déclaré.


### Résultat des essais Phase 7

Le run [42526327162](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42526327162)
est **en échec global** : le test de routage invité n'a pas observé de façon
fiable l'initiation WireGuard sur Android 10 et 15. Le TUN et la route ont été
observés dans certains essais précédents, ainsi qu'une initiation sur loopback,
mais les répétitions restent en échec ; la cause n'est pas établie.

Dans ce même run, le backend, les tests Go et `-race` sur Linux x86_64 et ARM64
natif, l'analyse et les tests Flutter, les tests unitaires Kotlin et la
compilation APK ont réussi. Le diagnostic Flutter → Kotlin → Go (désormais dans
un processus séparé) a réussi. Les tests du service propriétaire sur Android 10
et 15 x86_64 ont réussi trois répétitions : interface Android, démarrage moteur
local avec sockets protégées et liées au réseau cellulaire de l'émulateur,
coupure des données, arrêt, retour du réseau et redémarrage explicite. Ces
résultats ne valident ni réseau mobile physique ni transfert Internet. Les tests
VPN des nouveaux services sont ignorés sur Android 6 ; les tests JNI de base y
passent trois fois. Les journaux et un résumé de couverture sont conservés dans
l'artefact de diagnostic du run.

Dans le run [42517243752](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42517243752),
Android 15 a aussi subi un `SIGSEGV` après chargement des deux bibliothèques Go
et lors d'un essai propriétaire. La pile était insuffisante pour attribuer la
cause à leur coexistence. Par précaution, un garde interdit désormais de charger
les deux runtimes dans le même processus, même après arrêt d'un rôle ; le
diagnostic Flutter est isolé dans un autre processus. Basculer entre rôles dans
un même processus n'est donc pas encore pris en charge. Les essais propriétaire
et invité sont lancés dans des processus d'instrumentation distincts ; ceci ne
prouve pas la cause ni la résolution du plantage précédent.

Aucun téléphone physique n'a été testé. Le service propriétaire est un
prototype exécutable par les tests mais **n'est pas opérationnel comme service
de partage** ; les interfaces, l'acheminement complet, les clés, la révocation,
le relais et les tests de bout en bout restent bloquants.


## Phase 8 — diagnostic et état actuel

**Phase non validée. Partage désactivé.** Le run
[42575009419](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42575009419)
(commit `c8381c3`) est en échec : le test invité d'aller-retour échoue encore
sur Android 10 et 15 x86_64 après une première répétition réussie sur chaque
version. Il n'y a pas eu de téléphone physique, de réseau mobile physique ou
de test ARM Android. Le résultat n'est pas une preuve de stabilité en production.

### Trajet et propriété des paquets

* Invité : une application ordinaire écrit un datagramme IP ; le routage
  Android le dirige vers le TUN créé par `GoBackend.VpnService`. GoBackend
  détache son descripteur et le cède à wireguard-go, qui **lit** le TUN,
  chiffre et émet en UDP ; les réponses UDP reçues sont déchiffrées puis
  **écrites** dans ce TUN pour livraison à l'application. À l'arrêt, `wgTurnOff`
  ferme le moteur et son TUN ; le service termine ensuite sa destruction.
* Propriétaire : la socket UDP WireGuard est protégée et liée au réseau
  cellulaire demandé. WireGuard authentifie et déchiffre, puis **écrit** les
  IP invités dans le TUN en mémoire `bridge` ; gVisor les **lit** et termine
  les flux TCP/UDP, dont les sockets sortants doivent aussi être protégés et
  liés. gVisor **écrit** les réponses dans le TUN mémoire ; WireGuard les
  **lit**, chiffre et renvoie. Le TUN Android de contrôle du propriétaire est
  distinct, sans route Internet, et ne transporte pas les paquets invités.
* Les deux rôles ne doivent pas détenir simultanément le VPN Android. Le bail
  est en processus seulement et ne coordonne pas des processus séparés. Sur
  l'invité, `stop` attend désormais la disparition du service WireGuard avant
  de libérer ce bail ; en cas de doute il le conserve. Une révocation externe
  nécessite encore un appel explicite de nettoyage. Cette attente n'a pas
  résolu à elle seule les pertes intermittentes observées.

### Sonde et point de perte

Les annotations de [42526327162](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42526327162)
montrent que l'ancien `VpnProbeReceiver` Kotlin de l'APK de test lançait
`NoClassDefFoundError: kotlin.jvm.internal.Intrinsics` dans son propre processus :
la sonde n'était donc pas exécutée. Ce défaut précis du test ne prouve pas la
cause de tous les anciens timeouts, notamment ceux antérieurs à cette sonde.
Le récepteur est maintenant en Java autonome, avec accusé d'exécution, contrôle
de son UID distinct, vérification de la route et du réseau actif depuis cet
UID et vérification de la disparition de l'ancien VPN. Le test de l'initiation
ne peut plus réussir grâce à un datagramme de l'UID de l'application VPN.

Le nouveau pair de test est une vraie instance wireguard-go sur le runner, dont
la socket n'écoute que sur `127.0.0.1`. L'émulateur l'atteint par `10.0.2.2` ;
son TUN/netstack répond à l'adresse synthétique `198.18.0.1:5555`, sans
redirection ou sortie Internet. Les clés sont des vecteurs publics de test. Le
profil Android utilise `10.77.0.2/32`, MTU 1280, route `0.0.0.0/0`, et la
clé publique dérivée du pair. La route englobe l'endpoint afin de tester la
protection de sa socket ; le code amont appelle `protect` pour IPv4 et IPv6,
mais ne contrôle pas ses retours : les succès ponctuels ne couvrent pas un refus.

Dans les cycles réussis, le pair a reçu une initiation, émis une réponse,
reçu et déchiffré le datagramme puis chiffré l'écho ; le processus de l'APK
séparé a reçu le contenu et l'origine attendus. Dans les cycles échoués du
run ci-dessus, il voit un nouveau réseau VPN et sa route, `send` ne lève pas
d'erreur, mais la réception expire, les compteurs WireGuard invités restent
`tx=0 rx=0`, et le pair ne reçoit aucune initiation pour ce cycle. La perte
se situe donc **avant une émission WireGuard observée** ; les compteurs seuls
ne permettent pas de départager routage par UID, entrée/lecture du TUN, ou une
autre cause. Aucun timeout n'est converti en succès. Les réponses sont bien
réinjectées dans les cycles réussis, mais ce n'est pas reproductible.

Le test Go `TestWireGuardTCPUDPDNSRoundTrip` utilise deux vrais pairs et des
sockets loopback ; un décorateur compte les paquets effectivement lus et écrits
par leurs TUN sans modifier leur trajet. Il vérifie les quatre directions, la
mauvaise clé, TCP/UDP/DNS et la fermeture d'une connexion active. Les deux
runners Linux x86_64 et ARM64 ont passé les tests avec `-race` ; le dialer
local de test n'est pas le dialer cellulaire Android.

### Crash natif et choix d'architecture

La trace historique du [run 42517243752](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42517243752)
montre le chargement réussi des deux bibliothèques dans le même processus,
puis `signal 11`, sans pile native exploitable. L'analyse ELF de l'APK Phase 8
établit que `libgojni.so` est compilée avec Go 1.26.10 et wireguard-go
`f333402bd9cb`, tandis que `libwg-go.so` de l'AAR WireGuard embarque Go 1.20.3
et wireguard-go `21636207a675`. Sur x86_64 les deux exportent 31 symboles
dynamiques définis en commun, notamment `crosscall2`, `_cgo_*` et `x_cgo_*`.
Ce chevauchement et les deux versions de runtime sont des risques concrets à
étudier, **pas une preuve** d'interposition de symboles ni de la cause du
`SIGSEGV` : il manque la pile, les résolutions dynamiques à l'exécution et une
reproduction isolée. Le défaut de liaison `Network.bindSocket` des phases
précédentes était distinct ; demander un réseau cellulaire validé a permis des
démarrages sur émulateur, sans établir sa cause historique exacte.

La protection actuelle réserve irréversiblement un seul runtime Go par
processus ; le diagnostic Flutter s'exécute à part. Les tests des deux rôles
utilisent des processus d'instrumentation distincts, et les séries propriétaire
ne suffisent pas à innocenter le mélange des runtimes. Une architecture à un
seul runtime est envisageable, mais demande de reconstruire/intégrer les API
JNI de `GoBackend` et gomobile avec une version commune de wireguard-go, de
préserver le transfert de propriété du FD TUN, de rendre la protection vérifiable
et de retester concurrence, arrêt et licences. Ce n'est pas un simple changement
de dépendance, et elle n'a pas été implémentée sans preuve ni tests. Une autre
option serait un processus par rôle et un coordinateur unique interprocessus,
avec arrêt confirmé et consentement avant toute transition ; le bail actuel ne
suffit pas pour cela. Aucun basculement sûr entre rôles n'est encore proposé à
l'utilisateur.

### Couverture du dernier run

Backend, Flutter analyze/tests, canal Flutter–Kotlin–Go, tests unitaires Kotlin,
construction APK et ABI, tests Go `-race` Linux x86_64 et ARM64 et suites cœur
JNI Android 10/15 x86_64 passent. Le propriétaire y passe trois séries de
consentement automatisé, démarrage/arrêt et perte/retour cellulaire de
l'émulateur. Le test invité échoue à sa deuxième répétition sur les deux
versions ; les résultats précédents ne sont pas effacés. Android 6 x86 passe
les tests JNI de base, mais les tests VPN propriétaire/invité y sont ignorés
par condition d'API et ne constituent pas une validation VPN. Le diagnostic
Flutter avait échoué dans [42567387077](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42567387077),
puis a réussi dans les runs suivants : sa cause précédente reste inconnue.
Aucun nouveau crash natif n'est rapporté dans ces séries, ce qui ne démontre
pas l'absence générale de crash ou de fuite. Les essais ARM traduits n'ont pas
été lancés. Les résultats ELF ARM n'établissent que l'empaquetage, pas l'exécution.

## Phase 8.1 — instrumentation des cycles et état de validation

La série instrumentée `GuestCycleInstrumentedTest` vise 100 cycles sans
réessai : 50 sur un même objet invité puis 50 sur des objets neufs. Elle garde
un enregistrement JSONL par cycle, y compris les échecs, et vérifie notamment
l'UID de la sonde, l'écho, les octets et le handshake WireGuard côté invité,
l'arrêt du service, la disparition du VPN et la libération du bail. Elle
observe aussi les FD des sockets WireGuard, leur éventuelle fermeture, le nombre
de FD et de threads et les compteurs d'interface quand ils sont accessibles.
Ces compteurs noyau ne sont pas des compteurs de lecture du TUN par WireGuard.
Le `SO_MARK`, s'il est lisible, est un indice uniquement : ni sa présence ni
un bit particulier ne prouvent à eux seuls le succès de `VpnService.protect`.
Le journal du pair de test complète les traces ; les données diagnostiques et
les clés fixes de test ne sont pas des clés utilisateur. Une sonde liée au VPN
après certains échecs est uniquement différentielle, jamais un réessai de
succès. En cas d'arrêt ou d'appel natif d'état incertain, la série s'interrompt
sans démarrer un autre VPN : cela constitue un échec, pas 100 cycles réussis.
Le scénario séparé de perte/retour réseau peut lui aussi échouer ou être bloqué
par un nettoyage incertain.

Résultats confirmés, **pas une validation des 100 cycles** :

* [42600344830](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42600344830)
  teste `bcfc9e1` : les séries Android 10 et 15 expirent ; backend, Go Linux
  x86_64/ARM64 natif, Flutter, Kotlin, APK et Android 6 de base réussissent.
  [APK de développement](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42600344830/artifacts/13666235601),
  [diagnostics](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42600344830/artifacts/13670057168).
* [42606341576](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42606341576)
  (`a868c89`), [42611116194](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42611116194)
  (`e9135d4`) et [42611142575](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42611142575)
  (`5799b3d`) échouent également. Dans les deux derniers, Android 10 reste au
  cycle 0, après le jalon `inspect` ; le run `e9135d4` montre une expiration
  JUnit dans `libcore.io.Linux.readBytes`. La lecture du pipe de commande shell
  utilisé pour les compteurs est suspectée, sans que cela explique la perte
  intermittente du trafic VPN. Le scénario réseau suivant signale aussi que
  l'ancien VPN n'a pas disparu. Les séries 100/100 ne sont donc pas acquises.
* `44ac205` remplace cette lecture de compteur par une lecture sysfs bornée et
  corrige le repli d'extraction JSONL lorsque `run-as` renvoie une erreur sur
  stdout. `a297093` exige exactement les 100 identifiants de cycle et
  `5a759e4` limite les annotations tout en conservant les logs complets dans
  l'artifact. Les runs correspondants
  [42707384205](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42707384205),
  [42712900355](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42712900355)
  et [42713526877](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42713526877)
  n'étaient pas terminés lors de cette rédaction ; les étapes Android 10 des
  deux premiers et Android 15 du deuxième ont déjà échoué. Aucun décompte
  final ne peut en être déduit.
* `dce13da` borne les étapes émulateur et supprime le pipe `tee` susceptible de
  rester ouvert après timeout ; `d1dfead` ajuste ces limites pour laisser leur
  budget aux suites. Les runs [42713608334](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42713608334)
  et [42714183218](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42714183218)
  sont en cours au moment de la rédaction. Les changements de diagnostic et de
  CI ne constituent pas un correctif démontré de la perte VPN.

Le SIGSEGV historique et les limites de la section précédente restent ouverts.
Aucun essai sur Android ARM natif ou téléphone physique et aucun partage
Internet réel ne sont démontrés par ces séries x86_64.

## Phase 8.2 — protocole différentiel, sans correction supposée

Les deux sondes historiques sont créées par `VpnProbeReceiver` dans le processus
et sous l'UID de l'APK de test (différent de l'UID de l'application VPN). Chaque
broadcast ordonné lance son propre thread `vpn-test-probe`, qui crée un nouveau
`DatagramSocket()` après observation d'un réseau actif VPN avec une route vers
`198.18.0.1`. Le constructeur lie localement la socket à un port éphémère ; la
socket UDP n'est pas connectée, envoie à `198.18.0.1:5555`, attend l'écho
jusqu'à 4,5 s et est fermée par `try-with-resources`. Ni l'une ni l'autre ne
sont protégées par `VpnService.protect` : elles sont censées entrer dans le VPN.
La première utilise la sélection implicite du réseau ; la seconde vérifie le
handle VPN puis appelle `Network.bindSocket(socket)` avant l'envoi. Dans les
anciens essais, la seconde ne démarrait qu'après un timeout et utilisait donc
une autre socket, un autre port et un moment différent : son succès n'identifie
pas à lui seul l'effet de la liaison ou la cause de la perte.

Ceci est distinct des sockets UDP **externes** du tunnel WireGuard. Dans
l'AAR amont `1.0.20230706`, `GoBackend` établit le TUN et appelle `wgTurnOn`,
puis `VpnService.protect` sur les deux FD UDP du backend ; il n'en vérifie pas
les booléens. Il appelle `setUnderlyingNetworks(null)` et ne lie pas ces FD à
un `Network` explicite dans ce chemin Java. Le détail de connect/send interne
est dans le code natif de l'AAR. La protection vise à éviter une boucle dans le
VPN ; elle n'est pas la liaison de la sonde au VPN. Le code propriétaire
séparé protège puis lie ses sockets à un réseau cellulaire, mais n'est pas le
trajet invité étudié ici. Aucune modification de routage n'est proposée sans
preuve. Le SIGSEGV et l'exclusion des deux runtimes Go restent séparés.

Le nouveau test court effectue 30 cycles maximum, 15 par objet réutilisé puis
15 par objets neufs. Il envoie une sonde non liée et une autre liée par cycle,
en alternant leur ordre, et conserve chaque échec. Les deux échanges ont des
suffixes de test `A`/`B` pour corréler les paquets déchiffrés du pair ; le
second échange peut toutefois bénéficier d'un handshake établi par le premier,
et l'ordre, le temps et le port restent des variables. L'état du réseau actif,
les notifications `NetworkCallback`, les adresses/ports observables, l'UID, le
PID, les horaires et les statistiques WireGuard avant/après chaque sonde sont
consignés. L'enregistrement du callback est lui-même une instrumentation et
peut modifier les timings ; il ne prouve pas une route effective.

Le pair de test ajoute des compteurs à ses frontières TUN mémoire et socket UDP.
Un identifiant ne peut être associé aux paquets WireGuard chiffrés avant leur
déchiffrement : leurs événements portent `cycle=unavailable`. Les événements
TUN du pair corrèlent uniquement les charges de test reconnues, sans journaliser
les clés. Ces observations ne sont **pas** des compteurs du TUN Android. L'AAR
WireGuard Android précompilé n'expose pas de points d'instrumentation pour sa
lecture TUN, son émission/réception socket, son déchiffrement ou sa réinjection
TUN : ces valeurs sont explicitement `unavailable-upstream-aar`, pas zéro. La
mesure directe à ces points nécessiterait un backend instrumenté distinct,
construit et validé sans charger deux runtimes Go incompatibles ; elle n'est pas
implémentée ici. `SO_MARK` n'est pas une condition de réussite. Les statistiques
utilisées sont locales, et les appels de cycle sont bornés ; aucun shell n'est
utilisé pour lire des compteurs TUN.

Les séries de 100 cycles sont désactivées par défaut dans la CI. Une exécution
manuelle explicite reste possible après examen de la stabilité des essais courts,
et la série longue est alors conditionnée au succès des étapes précédentes.
Les résultats bruts et logs du pair vont dans l'artifact de diagnostic ; les
annotations résument les enregistrements et n'effacent aucun échec. Une absence
de 30 identifiants distincts est un échec, pas une preuve de stabilité.

### Résultats de reproduction courte

Le [run 42779305135](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42779305135)
(`0f846103fc5cb65069891749e3d49d28795dc9fa`) a reproduit des assertions
échouées sur les deux émulateurs : 4 cycles en échec sur Android 10 et 7 sur
Android 15, selon JUnit. Cependant plusieurs lignes JSON ont été tronquées par
la limite logcat : le résumé n'a reconstitué que 20/30 et 9/30 enregistrements
respectivement. Il ne faut pas en déduire que les autres cycles ont réussi.
`866a2ba` découpe les enregistrements en fragments numérotés et rejette les
fragments absents, dupliqués ou invalides ; les traces brutes du run initial
restent dans son artifact.

Le [run 42781884747](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42781884747)
(`866a2babd9d631256025a918f70cbb4528af4d3e`) est globalement en échec,
mais a reconstitué 30/30 lignes sur chaque émulateur, sans erreur de parsing :

| Émulateur | Écho implicite | Écho lié VPN | Cycles avec échec |
|---|---:|---:|---:|
| Android 10 x86_64 | 27/30 | 28/30 | 5/30 |
| Android 15 x86_64 | 27/30 | 26/30 | 7/30 |

Sur Android 10, le cycle 0 montre la sonde implicite réussie (UID 10135,
port local 60685, `tx=228 rx=172`) puis la sonde liée réussie ; le pair a
observé pour chacune écriture TUN mémoire, UDP déchiffré, envoi de l'écho et
lecture du TUN mémoire. Au cycle 6, toujours UID 10135, la première sonde
implicite envoie depuis le port 38711 mais expire avec `tx=0 rx=0` et sans
handshake ; aucun événement déchiffré du pair ne porte son identifiant `006:A`.
La seconde sonde, port 56917 liée au même handle VPN, reçoit l'écho ; son
identifiant `006:B` est observé aux quatre étapes du pair. Le service est alors
`DOWN`, non listé, et le bail libéré. Cela ne permet pas de localiser la perte
à l'intérieur du TUN Android ou du backend WireGuard.

L'ordre inverse est important : sur Android 15, cycle 5, la sonde **liée envoyée
la première échoue** avec `tx=0 rx=0`, puis la sonde **implicite réussit**.
Ceci invalide l'hypothèse que la liaison explicite suffit à corriger le défaut.
La notification `onAvailable` du VPN pour la première sonde du cycle 5 apparaît
après l'envoi ; au cycle 6 Android 10 elle apparaît aussi après l'envoi. Ces
observations suggèrent une transition asynchrone à étudier, mais ne prouvent pas
qu'elle cause la perte : le callback de diagnostic et les deux sondes ont leurs
propres files d'exécution, et la seconde sonde diffère aussi par son horaire et
son port. Les logs pair chiffrés ne sont pas attribuables individuellement aux
cycles. Aucune correction réseau ni temporisation arbitraire n'a été ajoutée.

Dans ce run, backend, Go `-race` Linux x86_64 et ARM64 natif, Flutter, Kotlin,
APK, suites JNI cœur/propriétaire, ancien test invité, perte/retour réseau et
Android 6 de base réussissent ; les séries courtes échouent. Android 6 ignore
les tests VPN conditionnés par l'API ; aucun ARM Android traduit ou physique
n'a été testé. La série de 100 cycles n'a pas été relancée. [Diagnostics](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42781884747/artifacts/13747790248)
et [APK de développement](https://github.com/leoblanchart92-hub/NexaLink/actions/runs/42781884747/artifacts/13746521769).
