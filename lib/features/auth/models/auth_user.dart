/// User role exactly as returned by the backend.
///
/// The authenticated backend is the **single source of truth** for the role;
/// the app never picks it or sends it manually.
class AuthRole {
  const AuthRole({required this.value, required this.label});

  /// Database value: `passenger`, `driver`, `company-admin`, `super-admin`.
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

  /// Roles that can use this app. Admin roles (`company-admin`, `super-admin`)
  /// work only in the admin panel.
  static const allowedRoles = {'passenger', 'driver'};

  /// UUID of the user in the Auth service.
  final String id;
  final String name;
  final String email;
  final List<AuthRole> roles;

  /// JSON:API response of the Auth service through the Gateway, requested with
  /// `?include=roles` (`POST /auth/login`, `POST /auth/register/passenger`,
  /// `GET /auth/user`):
  ///
  /// ```json
  /// {
  ///   "data": {"id": "<uuid>", "type": "users",
  ///            "attributes": {"name": "...", "email": "..."}},
  ///   "included": [{"type": "roles", "attributes": {"value": "passenger", "label": "Pasajero"}}]
  /// }
  /// ```
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

  /// Whether this user can use the app (passenger or driver).
  bool get isAllowedInApp => roles.any((r) => allowedRoles.contains(r.value));
}
