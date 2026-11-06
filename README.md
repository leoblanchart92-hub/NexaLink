# NexaLink — fondation expérimentale

**État : le partage Internet à distance et le VPN ne sont pas utilisables.** Des composants natifs WireGuard expérimentaux existent mais ne sont pas raccordés à l'interface ni testés sur appareils ; aucune passerelle ni relais n'est implémenté. Cette version ne transfère aucun trafic réseau d'un appareil à l'autre et ne doit pas être utilisée en production. L'application montre clairement cette limite.

## Ce qui existe

- Application Flutter Android : configuration d'un serveur HTTPS, création et lecture d'un QR d'invitation, demande explicite de l'invité, approbation/révocation par le propriétaire et consultation du statut d'association.
- Serveur Node.js/SQLite : codes aléatoires à usage unique, expirant au bout de cinq minutes ; jetons aléatoires stockés sous forme de hachages ; accès séparés propriétaire/invité ; contrôle d'appartenance ; approbation explicite. Les identifiants de l'application sont stockés avec `flutter_secure_storage` et l'app refuse les URL HTTP et les redirections.
- Préparation native : bibliothèque WireGuard Android, construction d'une configuration invitée, adaptateur de tunnel non exposé et primitives de sélection réseau cellulaire ; voir [l'étude technique et les limites](docs/architecture-reseau.md). Ces composants ne réalisent pas encore de partage.
- Tests automatisés du protocole d'association et workflow GitHub Actions pour construire un APK **de développement**, signé avec une clé debug. La présence du workflow ne prouve pas que la compilation ou l'installation fonctionne : vérifier son résultat.

L'association n'échange pas encore de clés WireGuard. Une approbation ou une révocation change seulement un état sur le serveur ; elle ne permet ni n'interrompt un tunnel existant. Ne partagez jamais un QR d'invitation publiquement. Le serveur d'association voit les noms choisis par les invités et les états d'association, pas les activités de navigation ; aucune infrastructure n'est fournie ou hébergée avec le dépôt.

## Récupérer l'APK de développement

Dans GitHub, ouvrez **Actions**, choisissez « Tests et APK Android (développement) », puis une exécution réussie de cette branche. Téléchargez l'artifact **NexaLink-android-development-apk** (archive ZIP), extrayez-le et installez `app-release.apk` sur Android. Les artifacts expirent après 14 jours ; le bouton « Run workflow » peut relancer la compilation. L'APK n'est pas destiné à la publication, et des builds debug-signés par des machines différentes ne sont pas forcément compatibles pour la mise à jour. Cette procédure est conditionnée à la réussite du job Android.

## Serveur d'association — développement uniquement

Node.js 22.13 ou plus récent est nécessaire. Sur une machine hébergeant le service :

```sh
cd backend
npm test
DB_PATH=/chemin/prive/nexalink.sqlite PORT=8080 npm start
```

Le serveur écoute uniquement sur `127.0.0.1` en HTTP. Pour l'utiliser depuis Android, un administrateur doit installer un reverse proxy HTTPS avec certificat valide et le diriger vers `127.0.0.1:8080`. L'application exige une origine HTTPS sans chemin (par exemple `https://exemple.fr`). Ne jamais exposer directement le port HTTP. Le service n'est pas prêt pour la production : il manque notamment administration, quotas persistants, suppression/rétention des données, sauvegardes chiffrées, protections anti-abus et audit de sécurité. Le limiteur intégré est local au processus et compte l'adresse du proxy : configurer une limitation adaptée sur le proxy (sans faire confiance aveuglément aux en-têtes transmis par le client). Désactiver les journaux d'accès du proxy, notamment les en-têtes Authorization et les corps des requêtes. Protéger le fichier SQLite et ses fichiers WAL, et sauvegarder le tout correctement.

Les jetons ne sont affichés qu'une fois et ne peuvent pas être récupérés. La désinstallation, la perte du téléphone ou le changement de serveur peut rendre impossible la gestion des anciennes associations ; il n'y a pas encore de récupération de compte. L'invité qui associe un nouvel appareil écrase sa précédente association locale. Un code expiré peut rester affiché, mais il est refusé par le serveur.

## Travail restant indispensable

1. Relier et tester le client WireGuard sur Android, implémenter le moteur propriétaire, la gestion locale des clés, le consentement Android `VpnService`, l’échange authentifié des clés et la révocation effective côté tunnel.
2. Développer et tester le plan de données : relais pour NAT mobiles, protection des sockets contre les boucles VPN, transport chiffré, transfert et traduction du trafic sur le téléphone propriétaire, DNS, IPv4/IPv6, MTU, reconnexion et limites Android. Un relais classique WireGuard ne transforme pas à lui seul le téléphone propriétaire en routeur Internet ; une application Android ordinaire ne peut pas supposer qu'elle dispose de l'IP forwarding ou de privilèges root. Une solution en espace utilisateur doit être étudiée et vérifiée sur de vrais appareils. Le trafic devra effectivement sortir par la connexion mobile du propriétaire ; le forfait et l'opérateur peuvent imposer des restrictions et des frais.
3. Ajouter mesures réelles de connexion et de consommation, gestion du cycle de vie/notifications Android, comptes récupérables et protections serveur, tests de sécurité, et signatures de publication.
4. Vérifier en conditions réelles sur au moins deux téléphones, réseaux mobiles distincts et derrière NAT, avec et sans relais : sortie Internet, confidentialité, consentement et interruption après révocation. Rien de cela n'a encore été validé.

## Développement

Avec Flutter 3.24.5 et le SDK Android installés : `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --release`. Test du backend : `cd backend && npm test`. Le dépôt ne contient pas de secrets de production ni d'APK précompilé.
