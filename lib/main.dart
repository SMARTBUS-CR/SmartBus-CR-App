import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/auth/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/verify_email_screen.dart';
import 'features/passenger/passenger_home_screen.dart';
import 'features/passenger/route_search_screen.dart';
import 'features/passenger/bus_tracking_screen.dart';
import 'features/passenger/buses_in_progress_screen.dart';
import 'features/operations/models/operations_models.dart';
import 'features/passenger/passenger_trips_screen.dart';
import 'features/passenger/passenger_account_screen.dart';
import 'features/passenger/edit_profile_screen.dart';
import 'features/passenger/change_password_screen.dart';
import 'features/auth/models/auth_user.dart';
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
    '/passenger/buses': (_) => const BusesInProgressScreen(),
    '/passenger/trips': (_) => const PassengerTripsScreen(),
    '/passenger/account': (_) => const PassengerAccountScreen(),
    '/passenger/account/password': (_) => const ChangePasswordScreen(),

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
          // From Home: the picked trip. From the tab: none (the screen looks
          // for the trip in progress).
          final args = settings.arguments;
          builder = (_) => args is TripScreenArgs
              ? TripScreen(trip: args.trip, autoStart: args.autoStart)
              : const TripScreen();
        } else if (settings.name == '/passenger/tracking') {
          // Needs the trip UUID (from "Buses en curso").
          final args = settings.arguments;
          if (args is! String) return null;
          builder = (_) => BusTrackingScreen(tripId: args);
        } else if (settings.name == '/passenger/route') {
          // Route detail (directions, stops, buses running), from the search.
          final args = settings.arguments;
          if (args is! TransitRoute) return null;
          builder = (_) => RouteBusesScreen(route: args);
        } else if (settings.name == '/verify-email') {
          final args = settings.arguments;
          // Needs the email to verify; without it there is nothing to show.
          if (args is! VerifyEmailArgs) return null;
          builder = (_) => VerifyEmailScreen(args: args);
        } else if (settings.name == '/passenger/account/edit') {
          final args = settings.arguments;
          // Needs the current profile to pre-fill the form.
          if (args is! AuthUser) return null;
          builder = (_) => EditProfileScreen(user: args);
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
      // A route without its arguments (e.g. `/passenger/tracking` without the
      // trip id) or an unknown name: instead of an exception, the splash
      // sends the user to the home of their role (or to login).
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const SplashScreen(),
      ),
    );
  }
}
