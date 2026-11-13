import '../../operations/models/operations_models.dart';

/// A route the passenger saved as favorite (`GET ops/favorites`).
///
/// The Dashboard returns `favorite-routes` resources whose `route` (and the
/// route's `company`) come in the JSON:API `included` array.
class FavoriteRoute {
  const FavoriteRoute({
    required this.id,
    required this.route,
    this.label,
    this.companyName,
    this.savedAt,
  });

  /// [included] is the document's `included` array. Without the route there,
  /// only its id is known (code and name stay empty).
  factory FavoriteRoute.fromJsonApi(
    Map<String, dynamic> resource, [
    Object? included,
  ]) {
    final attributes = _map(resource['attributes']);
    final byKey = _index(included);

    final routeId =
        _string(attributes['route_id']) ?? _linkedId(resource, 'route') ?? '';
    final routeResource = byKey['routes:$routeId'];
    final route = routeResource != null
        ? TransitRoute.fromJsonApi(routeResource)
        : TransitRoute(id: routeId, code: '', name: '');

    final companyId = routeResource == null
        ? null
        : _linkedId(routeResource, 'company') ??
              _string(_map(routeResource['attributes'])['company_id']);
    final company = _map(byKey['companies:$companyId']?['attributes']);

    return FavoriteRoute(
      id: resource['id'].toString(),
      route: route,
      label: _string(attributes['label']),
      companyName:
          _string(company['trade_name']) ?? _string(company['legal_name']),
      savedAt: DateTime.tryParse(_string(attributes['created_at']) ?? ''),
    );
  }

  /// Favorite with only the route known: what the app shows right after the
  /// star is tapped, before the server answers.
  factory FavoriteRoute.pending(TransitRoute route, {String? label}) =>
      FavoriteRoute(
        id: '',
        route: route,
        label: label,
        savedAt: DateTime.now(),
      );

  /// Id of the favorite itself (not of the route).
  final String id;

  final TransitRoute route;
  String get routeId => route.id;

  /// Optional alias the passenger gave it ("Trabajo").
  final String? label;

  /// Operator (trade name), when the company was included.
  final String? companyName;

  /// When it was saved; the list shows the most recent first.
  final DateTime? savedAt;

  /// Copy with another alias (`null` = none).
  FavoriteRoute withLabel(String? newLabel) => FavoriteRoute(
    id: id,
    route: route,
    label: newLabel,
    companyName: companyName,
    savedAt: savedAt,
  );

  /// What the list shows as the title: the alias, else the route name.
  String get title => label ?? (route.name.isEmpty ? 'Ruta' : route.name);

  /// Copy with the route details the app already had (the server may not
  /// include them in the POST answer).
  FavoriteRoute withRoute(TransitRoute known) => FavoriteRoute(
    id: id,
    route: route.code.isEmpty && route.name.isEmpty ? known : route,
    label: label,
    companyName: companyName,
    savedAt: savedAt,
  );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

String? _string(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// `included` by "type:id".
Map<String, Map<String, dynamic>> _index(Object? included) => {
  if (included is List)
    for (final item in included.whereType<Map>())
      if (item['type'] != null && item['id'] != null)
        '${item['type']}:${item['id']}': Map<String, dynamic>.from(item),
};

/// Id of a to-one relationship (`relationships.<name>.data.id`).
String? _linkedId(Map<String, dynamic> resource, String name) {
  final data = _map(_map(resource['relationships'])[name])['data'];
  return data is Map ? _string(data['id']) : null;
}
