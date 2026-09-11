import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Full-width call-to-action button with the SmartBus brand gradient
/// (corporate blue → primary blue → turquoise).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient = SmartBusColors.brandGradient,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient gradient;

  /// Shows a spinner and blocks taps (e.g. while permission is being requested).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final active = onPressed != null && !busy;

    return Opacity(
      opacity: active ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color:
                        SmartBusColors.azulPrincipal.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: active ? onPressed : null,
            child: SizedBox(
              height: 52,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(
                            SmartBusColors.blanco,
                          ),
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, color: SmartBusColors.blanco, size: 22),
                    if (busy || icon != null) const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        color: SmartBusColors.blanco,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
