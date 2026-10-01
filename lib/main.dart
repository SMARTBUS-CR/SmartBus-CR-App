import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'features/auth/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/passenger/passenger_home_screen.dart';
import 'features/passenger/route_search_screen.dart';
import 'features/passenger/bus_tracking_screen.dart';
import 'features/passenger/passenger_trips_screen.dart';
import 'features/passenger/passenger_account_screen.dart';
import 'features/driver/driver_home_screen.dart';
import 'features/driver/trip_screen.dart';
import 'features/driver/driver_routes_screen.dart';
import 'features/driver/driver_account_screen.dart';

void main() => runApp(const SmartBusApp());

class SmartBusApp extends StatelessWidget {
  const SmartBusApp({super.key});

  static final Map<String, WidgetBuilder> _routes = {
    '/splash': (_) => const SplashScreen(),
    '/login': (_) => const LoginScreen(),
    '/register': (_) => const RegisterScreen(),

    // Passenger flow (RF-07 to RF-12)
    '/passenger/home': (_) => const PassengerHomeScreen(),
    '/passenger/search': (_) => const RouteSearchScreen(),
    '/passenger/tracking': (_) => const BusTrackingScreen(),
    '/passenger/trips': (_) => const PassengerTripsScreen(),
    '/passenger/account': (_) => const PassengerAccountScreen(),

    // Driver flow (RF-13 to RF-15)
    '/driver/home': (_) => const DriverHomeScreen(),
    '/driver/trip': (_) => const TripScreen(),
    '/driver/routes': (_) => const DriverRoutesScreen(),
    '/driver/account': (_) => const DriverAccountScreen(),
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartBus',
      debugShowCheckedModeBanner: false,
      theme: SmartBusTheme.light,
      initialRoute: '/splash',
      onGenerateRoute: (settings) {
        final WidgetBuilder? builder;
        if (settings.name == '/driver/trip') {
          final args = settings.arguments;
          final autoStart = args is Map && args['autoStart'] == true;
          builder = (_) => TripScreen(autoStart: autoStart);
        } else {
          builder = _routes[settings.name];
        }
        if (builder == null) return null;
        final resolved = builder;
        return PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) =>
              resolved(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        );
      },
    );
  }
}
