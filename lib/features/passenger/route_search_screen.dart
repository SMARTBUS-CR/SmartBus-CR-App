import 'package:flutter/material.dart';

import '../../widgets/placeholder_screen.dart';
import '../../widgets/smartbus_header.dart';

class RouteSearchScreen extends StatelessWidget {
  const RouteSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Buscar Ruta',
      icon: Icons.search,
      subtitle: 'Aquí podrás buscar tu ruta por nombre, número o destino.',
      type: SmartBusUserType.passenger,
      onBack: () => Navigator.pushReplacementNamed(context, '/passenger/home'),
    );
  }
}
