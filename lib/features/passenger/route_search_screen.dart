import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/placeholder_screen.dart';

class RouteSearchScreen extends StatelessWidget {
  const RouteSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlaceholderScreen(
      title: 'Buscar Ruta',
      icon: Icons.search,
      subtitle: 'Aquí podrás buscar tu ruta por nombre, número o destino.',
      color: SmartBusColors.verdeMenta,
      onBack: () => Navigator.pushReplacementNamed(context, '/passenger/home'),
    );
  }
}
