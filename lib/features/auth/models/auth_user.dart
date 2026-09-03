/// User role exactly as returned by the backend.
///
/// The authenticated backend is the **single source of truth** for the role;
/// the app never picks it or sends it manually.
class AuthRole {
  const AuthRole({required this.value, required this.label});

  /// Database value: `passenger`, `driver`, `admin`, …
  final String value;

  /// Display label: `Pasajero`, `Conductor`, …
  final String label;

  factory AuthRole.fromJson(Map<String, dynamic> json) => AuthRole(
        value: (json['value'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

/// Authenticated SmartBus Global user.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.roles = const [],
  });

  final String id;
  final String name;
  final String email;
  final List<AuthRole> roles;

  /// JSON:API response from the Auth service through the Gateway
  /// (`POST /auth/login` with `?include=roles`).
  factory AuthUser.fromJsonApi(Map<String, dynamic> body) {
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    final attributes =
        (data['attributes'] as Map<String, dynamic>?) ?? const {};

    final included = (body['included'] as List?) ?? const [];
    final roles = included
        .whereType<Map<String, dynamic>>()
        .where((r) => r['type'] == 'roles')
        .map((r) => AuthRole.fromJson(
              (r['attributes'] as Map<String, dynamic>?) ?? const {},
            ))
        .where((r) => r.value.isNotEmpty)
        .toList();

    return AuthUser(
      id: (data['id'] ?? '').toString(),
      name: (attributes['name'] ?? '').toString(),
      email: (attributes['email'] ?? '').toString(),
      roles: roles,
    );
  }

  /// "Flattened" Gateway response for `GET /auth/user` → `{id, email, name}`.
  /// That Gateway endpoint does not include roles, so the [fallbackRoles] stored
  /// at login time are kept.
  factory AuthUser.fromGatewayProfile(
    Map<String, dynamic> body, {
    List<AuthRole> fallbackRoles = const [],
  }) {
    return AuthUser(
      id: (body['id'] ?? '').toString(),
      name: (body['name'] ?? '').toString(),
      email: (body['email'] ?? '').toString(),
      roles: fallbackRoles,
    );
  }

  /// Rebuilds the user from local secure storage.
  factory AuthUser.fromStorage(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        roles: ((json['roles'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AuthRole.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'roles': roles.map((r) => r.toJson()).toList(),
      };

  AuthUser copyWith({String? name, String? email, List<AuthRole>? roles}) =>
      AuthUser(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        roles: roles ?? this.roles,
      );

  AuthRole? get primaryRole => roles.isNotEmpty ? roles.first : null;

  bool hasRole(String value) => roles.any((r) => r.value == value);
  bool get isPassenger => hasRole('passenger');
  bool get isDriver => hasRole('driver');
  bool get isAdmin => hasRole('admin');
}
