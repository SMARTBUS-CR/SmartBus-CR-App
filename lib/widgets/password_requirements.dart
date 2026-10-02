import 'package:flutter/material.dart';

import '../core/theme.dart';

/// One password rule of the Auth service (`Password::min(8)->mixedCase()
/// ->numbers()->symbols()`).
class PasswordRule {
  const PasswordRule(this.label, this.isMet);

  final String label;
  final bool Function(String password) isMet;

  /// Same rules as the backend. `uncompromised()` cannot be checked in the
  /// app: it comes back as a 422 from the server.
  static final all = <PasswordRule>[
    PasswordRule('Mínimo 8 caracteres', (p) => p.length >= 8),
    PasswordRule('Una letra mayúscula', (p) => p.contains(RegExp(r'[A-Z]'))),
    PasswordRule('Una letra minúscula', (p) => p.contains(RegExp(r'[a-z]'))),
    PasswordRule('Un número', (p) => p.contains(RegExp(r'[0-9]'))),
    PasswordRule(
      r'Un símbolo (ej. # ! @ $)',
      (p) => p.contains(RegExp(r'[^A-Za-z0-9]')),
    ),
  ];

  /// Rules the [password] does not meet yet.
  static List<PasswordRule> missing(String password) =>
      all.where((rule) => !rule.isMet(password)).toList();
}

/// Vertical checklist of the password rules.
///
/// It appears (animated) as soon as the user starts typing the password and
/// each rule switches from pending to met in real time, using the theme
/// colors: corporate blue while pending, turquoise once met.
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final password = value.text;

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: password.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10, left: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final rule in PasswordRule.all)
                        _RuleItem(label: rule.label, met: rule.isMet(password)),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem({required this.label, required this.met});

  final String label;
  final bool met;

  static const _pending = SmartBusColors.azulCorporativo;
  static const _done = SmartBusColors.verdeTurquesa;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              met ? Icons.check_circle : Icons.radio_button_unchecked,
              key: ValueKey(met),
              size: 16,
              color: met ? _done : _pending.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 12,
                fontWeight: met ? FontWeight.w600 : FontWeight.w400,
                color: met ? SmartBusColors.verdeMenta : _pending,
              ),
              child: Text(label),
            ),
          ),
        ],
      ),
    );
  }
}
