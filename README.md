# NexaLink

**Partage Internet Mobile Sécurisé à Distance via WireGuard VPN**

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android-blue?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Flutter-3.16+-02569B?style=for-the-badge&logo=flutter" />
  <img src="https://img.shields.io/badge/WireGuard-Tunnel-88171A?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" />
</p>

---

## 🌐 Description

**NexaLink** est une application Android permettant de partager la connexion Internet mobile 4G/5G d'un téléphone propriétaire avec un téléphone invité, même à plusieurs kilomètres de distance, grâce à un tunnel VPN WireGuard sécurisé.

### Fonctionnalités Principales

- 🔐 **Tunnel WireGuard** - Chiffrement de bout en bout Curve25519/ChaCha20
- 📱 **Mode Propriétaire** - Contrôlez le partage, gérez les invités, monitorer la connexion
- 📲 **Mode Invité** - Scannez un QR code pour se connecter instantanément
- 📊 **Tableau de Bord** - Stats en temps réel, vitesse, latence, consommation
- 🔑 **Association QR** - Pairing sécurisé en un scan
- 🛡️ **Sécurité** - Consentement mutuel, clés temporaires, révocation d'accès
- 🎨 **Design Moderne** - Interface sombre avec accents bleu électrique et violet

## 📐 Architecture

```
┌─────────────────┐         WireGuard Tunnel         ┌─────────────────┐
│  TÉLÉPHONE      │ ◄══════════════════════════════► │  TÉLÉPHONE      │
│  PROPRIÉTAIRE   │     (chiffré, via UDP 51820)     │     INVITÉ      │
│                 │                                    │                 │
│  4G/5G ─────────┤──► Internet partagé via tunnel   ├──► Tout trafic   │
│                 │                                    │    via tunnel   │
└─────────────────┘                                    └─────────────────┘
         ▲                                                     ▲
         │              ┌──────────────────┐                   │
         └──────────────│  Serveur Relais  │◄──────────────────┘
            (optionnel) │  (signalisation) │   (optionnel)
                        │  échange de clés │
                        └──────────────────┘
```

### Flux de Connexion

1. **Propriétaire** démarre le mode partage → génère ses clés WireGuard
2. **Propriétaire** génère un QR code contenant sa clé publique et son endpoint
3. **Invité** scanne le QR code → reçoit les infos de connexion
4. **Invité** génère ses propres clés → envoie sa clé publique au propriétaire
5. **Tunnel WireGuard** est établi entre les deux appareils
6. **Propriétaire** active le forwarding IP → la connexion Internet est partagée

## 🛠️ Technologies

| Composant | Technologie |
|-----------|-------------|
| Framework | Flutter 3.16+ / Dart 3 |
| Platform | Kotlin (Android) |
| VPN | WireGuard (VpnService Android) |
| Crypto | Curve25519, ChaCha20-Poly1305 |
| State | Provider / Riverpod |
| Stockage | Hive / SharedPreferences |
| QR | qr_flutter / mobile_scanner |
| Build | Gradle 8.3 / GitHub Actions |

## 📥 Installation

### Via GitHub Releases (Recommandé)

1. Allez sur la page [Releases](https://github.com/leoblanchart92-hub/NexaLink/releases)
2. Téléchargez `NexaLink-release.apk`
3. Sur votre téléphone Android :
   - Activez **Paramètres → Sécurité → Sources inconnues**
   - Installez l'APK téléchargé

### Build depuis les sources

```bash
# Cloner le dépôt
git clone https://github.com/leoblanchart92-hub/NexaLink.git
cd NexaLink

# Installer Flutter (si nécessaire)
# https://docs.flutter.dev/get-started/install

# Récupérer les dépendances
flutter pub get

# Builder le APK debug
flutter build apk --debug

# Builder le APK release
flutter build apk --release

# Le APK se trouve dans:
# build/app/outputs/flutter-apk/app-release.apk
```

## 📖 Guide d'Utilisation

### Mode Propriétaire (Partage de connexion)

1. Ouvrez NexaLink → sélectionnez **Mode Propriétaire**
2. Appuyez sur le bouton central pour **activer le tunnel VPN**
3. Appuyez sur **QR Code** pour générer le code de pairing
4. Montrez le QR code à l'appareil invité
5. Une fois l'invité connecté, vous verrez son appareil dans la liste
6. Gérez les invités : révoquez ou supprimez des accès

### Mode Invité (Connexion à distance)

1. Ouvrez NexaLink → sélectionnez **Mode Invité**
2. **Scannez le QR code** du propriétaire
3. La connexion VPN se configure automatiquement
4. Appuyez sur le bouton pour **activer la connexion**
5. Internet du propriétaire est maintenant accessible via le tunnel

## 🔒 Sécurité

- **Chiffrement** : WireGuard utilise Curve25519 pour l'échange de clés et ChaCha20-Poly1305 pour le chiffrement des données
- **Authentification** : Chaque appareil possède une paire de clés unique
- **Consentement** : Les deux appareils doivent approuver la connexion
- **Révocation** : Le propriétaire peut révoquer l'accès à tout moment
- **Confidentialité** : Aucune collecte de données personnelles, aucune surveillance

## 🏗️ Structure du Projet

```
NexaLink/
├── lib/
│   ├── main.dart                    # Point d'entrée
│   ├── config/
│   │   ├── theme.dart               # Design system
│   │   ├── constants.dart           # Constantes
│   │   └── routes.dart              # Navigation
│   ├── models/
│   │   ├── device.dart              # Modèle appareil
│   │   ├── vpn_config.dart          # Config WireGuard
│   │   └── connection_stats.dart    # Stats connexion
│   ├── services/
│   │   ├── app_provider.dart        # State management
│   │   ├── wireguard_service.dart   # Gestion VPN
│   │   ├── signal_service.dart      # Signalisation
│   │   ├── qr_service.dart          # QR code
│   │   └── storage_service.dart     # Stockage local
│   ├── screens/
│   │   ├── splash_screen.dart       # Écran de démarrage
│   │   ├── home_screen.dart         # Sélection de mode
│   │   ├── owner_mode/              # Mode propriétaire
│   │   └── guest_mode/              # Mode invité
│   └── widgets/                     # Composants UI
├── android/
│   └── app/src/main/kotlin/.../
│       ├── MainActivity.kt          # Activity principale
│       └── NexaLinkVpnService.kt    # Service VPN Android
├── .github/workflows/
│   └── build-apk.yml                # CI/CD
└── pubspec.yaml                     # Dépendances
```

## 🤝 Contribution

Les contributions sont les bienvenues ! 

1. Forkez le projet
2. Créez une branche (`git checkout -b feature/AmazingFeature`)
3. Commitez (`git commit -m 'Add AmazingFeature'`)
4. Pushez (`git push origin feature/AmazingFeature`)
5. Ouvrez une Pull Request

## 📄 Licence

Ce projet est sous licence MIT. Voir [LICENSE](LICENSE) pour plus de détails.

## ⚠️ Avertissement

- L'utilisation d'un VPN peut être soumise à des réglementations locales
- Le partage de connexion mobile peut consommer des données importantes
- Assurez-vous d'avoir l'autorisation du propriétaire de la connexion
- Cette application ne doit pas être utilisée pour des activités illégales
# Retry build
