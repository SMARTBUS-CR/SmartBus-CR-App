/// Modelos alineados 1:1 con las respuestas de
/// SmartBus Authentication API (POST /login, POST /register/passenger, GET /user)

class AppRole {
  final String value; // ej: "passenger", "driver", "admin"
  final String label;

  AppRole({required this.value, required this.label});

  factory AppRole.fromJson(Map<String, dynamic> json) => AppRole(
        value: json['value'] as String,
        label: json['label'] as String,
      );
}

class AppUser {
  final int id;
  final String name;
  final String email;
  final List<AppRole> roles;
  final List<String> permissions;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.roles,
    required this.permissions,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        roles: (json['roles'] as List)
            .map((r) => AppRole.fromJson(r as Map<String, dynamic>))
            .toList(),
        permissions: (json['permissions'] as List).cast<String>(),
      );

  bool get isDriver => roles.any((r) => r.value == 'driver');
  bool get isPassenger => roles.any((r) => r.value == 'passenger');
}

class AuthSession {
  final String accessToken;
  final String tokenType;
  final AppUser? user; // /login no siempre trae "user" anidado, /register sí

  AuthSession({required this.accessToken, required this.tokenType, this.user});
}
