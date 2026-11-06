# Étude du moteur réseau NexaLink

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
unitaires du contrôleur utilisent un moteur de test et ne prouvent pas le cycle
réel d'un service Android, la perte réseau ou l'absence de fuite.

Aucun service propriétaire n'est enregistré ou démarré, et le contrôleur n'est
pas relié aux commandes Flutter. L'invité conserve l'adaptateur `GuestTunnel`
existant et le backend `GoBackend` de WireGuard : il faut encore obtenir le
consentement Android, un profil authentifié, et valider son cycle de vie réel.
Le QR n'a pas été modifié ; il ne doit jamais contenir de clé privée. L'échange
authentifié des clés publiques, la vérification de l'identité, la révocation
réelle et l'intégration des services restent à concevoir et tester avant toute
activation. Aucun de ces composants ne permet actuellement de partager Internet.
