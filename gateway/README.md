# Prototype local de passerelle

Code expérimental : un AAR gomobile et un adaptateur Kotlin sont compilés avec l'APK, mais le démarrage du partage n'est pas exposé dans l'application. `Gateway` connecte un TUN en mémoire de wireguard-go aux handlers TCP/UDP de tun2socks/gVisor. Le programme appelant doit configurer WireGuard avec la clé du pair et `AllowedIPs` correspondant à l'unique adresse invitée /32, et fournir une fonction de connexion explicitement liée à la connexion cellulaire. Aucun dialer par défaut ni relais n'est fourni. `PublicIPv4` est une première politique restrictive, pas un audit de sécurité. La bibliothèque n'est pas prête à servir des invités réels.

Le test d'intégration lance deux vrais appareils wireguard-go en mémoire via UDP local, un invité et une passerelle, avec des serveurs TCP/UDP/DNS de test sur loopback. Il ne démontre pas la sortie mobile Android, la traversée de NAT ou la sécurité de production. Aucun réseau public n'est contacté par le test. Une adresse de destination synthétique est redirigée par un dialer de test exclusivement vers les serveurs loopback ; la politique de production proposée interdit loopback.

Le pont JNI existe, mais il n'y a pas de service propriétaire opérationnel, de gestion de perte réseau, d'échange authentifié des clés et consentements, de révocation par invité ni de relais. Ne pas brancher ce prototype à l'application avant de sécuriser ces éléments et de tester la liaison cellulaire et la fermeture en cas de perte réseau. IPv4 TCP/UDP uniquement, les fragments IP, ICMP et IPv6 sont rejetés ; les résolutions DNS passent en UDP/TCP comme des flux ordinaires vers le serveur configuré par l'invité.

## Pont Android expérimental

`mobile.Engine` démarre un endpoint WireGuard pour un pair et utilise le moteur de ce dossier. La liaison doit recevoir un callback Kotlin qui protège les descripteurs et les lie à un réseau cellulaire validé ; tout refus interrompt l'opération. Ce contrat et l'appel Kotlin/Go sont vérifiés par tests, mais pas la sélection ou l'utilisation d'un réseau mobile physique. `OwnerEngineAdapter` exige un `VpnService` autorisé et un `Network`, mais aucun service ni gestionnaire de cycle de vie ne l'instancie encore. Il ne faut pas le connecter aux boutons sans gestion de perte réseau, révocation, authentification des pairs et validation de sécurité. Les compteurs disponibles sont des octets WireGuard, pas une preuve de sortie Internet.

Le workflow CI génère l'AAR via gomobile pour arm64, arm, x86_64 et x86, puis l'utilise pour compiler l'APK ; l'AAR n'est pas commité. Des tests sur émulateur vérifient le chargement JNI, l'appel de callback, le refus de démarrer sans protection et le démarrage/arrêt local avec un callback de test volontairement permissif. **Ce callback de test ne prouve pas la protection VPN ou la sortie cellulaire et ne doit jamais être utilisé en production.**

## Stabilité et compilation

Go 1.26 au minimum est requis : les versions antérieures ont un défaut
cgo connu ([golang/go#46893](https://github.com/golang/go/issues/46893))
suspecté dans les plantages observés. La CI utilise Go 1.26.10 et conserve
les journaux des tests instrumentés. Une réussite des tests ne prouve ni
l'absence de fuite mémoire ni la stabilité sur toutes les architectures.
Le moteur reste expérimental et le partage désactivé.

L'API ne permet pas de décharger/recharger de façon fiable la bibliothèque
native dans un processus Android ; les tests répètent la création d'objets et
le démarrage/arrêt, sans présenter cela comme un déchargement. Les appels sont
sérialisés par le verrou Go : un arrêt demandé pendant un callback de démarrage
attend que ce callback revienne ; il ne l'interrompt pas. Un futur service devra
gérer ce délai et la disparition du réseau sans bloquer le thread principal.
