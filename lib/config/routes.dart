import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/owner_mode/owner_dashboard.dart';
import '../screens/owner_mode/generate_qr_screen.dart';
import '../screens/owner_mode/manage_guests_screen.dart';
import '../screens/guest_mode/scan_qr_screen.dart';
import '../screens/guest_mode/guest_dashboard.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/statistics/statistics_screen.dart';
import '../screens/auth/pin_lock_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String home = '/home';
  static const String ownerDashboard = '/owner';
  static const String generateQr = '/owner/generate-qr';
  static const String manageGuests = '/owner/guests';
  static const String scanQr = '/guest/scan';
  static const String guestDashboard = '/guest';
  static const String settings = '/settings';
  static const String onboarding = '/onboarding';
  static const String statistics = '/statistics';
  static const String pinLock = '/pin-lock';
  static const String setPin = '/set-pin';

  static Map<String, WidgetBuilder> get routes => {
        splash: (context) => const SplashScreen(),
        home: (context) => const HomeScreen(),
        ownerDashboard: (context) => const OwnerDashboard(),
        generateQr: (context) => const GenerateQrScreen(),
        manageGuests: (context) => const ManageGuestsScreen(),
        scanQr: (context) => const ScanQrScreen(),
        guestDashboard: (context) => const GuestDashboard(),
        settings: (context) => const SettingsScreen(),
        onboarding: (context) => const OnboardingScreen(),
        statistics: (context) => const StatisticsScreen(),
        pinLock: (context) => const PinLockScreen(isVerify: true),
        setPin: (context) => const PinLockScreen(isVerify: false),
      };

  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case ownerDashboard:
        return MaterialPageRoute(builder: (_) => const OwnerDashboard());
      case generateQr:
        return MaterialPageRoute(builder: (_) => const GenerateQrScreen());
      case manageGuests:
        return MaterialPageRoute(builder: (_) => const ManageGuestsScreen());
      case scanQr:
        return MaterialPageRoute(builder: (_) => const ScanQrScreen());
      case guestDashboard:
        return MaterialPageRoute(builder: (_) => const GuestDashboard());
      case settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());
      case statistics:
        return MaterialPageRoute(builder: (_) => const StatisticsScreen());
      case pinLock:
        return MaterialPageRoute(builder: (_) => const PinLockScreen(isVerify: true));
      case setPin:
        return MaterialPageRoute(builder: (_) => const PinLockScreen(isVerify: false));
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Route not found: ${routeSettings.name}'),
            ),
          ),
        );
    }
  }
}
