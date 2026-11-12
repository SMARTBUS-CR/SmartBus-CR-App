import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/passenger/services/favorites_service.dart';

const _routeA = 'a0500000-0000-4000-8000-00000000000a';
const _routeB = 'a0500000-0000-4000-8000-00000000000b';
const _company = 'c0100000-0000-4000-8000-000000000001';

/// A `favorite-routes` resource as the Dashboard returns it.
Map<String, dynamic> _favorite(String routeId, String createdAt) => {
  'id': 'fav-$routeId',
  'type': 'favorite-routes',
  'attributes': {
    'user_id': 'someone',
    'route_id': routeId,
    'label': routeId == _routeA ? 'Trabajo' : null,
    'created_at': createdAt,
    'updated_at': createdAt,
  },
  'relationships': {
    'route': {
      'data': {'type': 'routes', 'id': routeId},
    },
  },
};

Map<String, dynamic> _route(String id, String code, String name) => {
  'id': id,
  'type': 'routes',
  'attributes': {'code': code, 'name': name, 'company_id': _company},
  'relationships': {
    'company': {
      'data': {'type': 'companies', 'id': _company},
    },
  },
};

final _company1 = {
  'id': _company,
  'type': 'companies',
  'attributes': {'legal_name': 'Transportes S.A.', 'trade_name': 'TUASA'},
};

class _Harness {
  _Harness(this.respond) {
    service = FavoritesService(
      client: ApiClient(
        sessionStore: SecureSessionStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          final (status, body) = respond(request);
          return http.Response(
            body == null ? '' : jsonEncode(body),
            status,
            headers: {
              'content-type': 'application/vnd.api+json; charset=utf-8',
            },
          );
        }),
      ),
    );
  }

  final (int, Object?) Function(http.Request) respond;
  final List<http.Request> requests = [];
  late final FavoritesService service;
}

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'sb_access_token': 'tok-123',
    }),
  );

  test('AC2 + AC3 · GET ops/favorites with the token and no user id; '
      'route, company and label from included; most recent first', () async {
    final h = _Harness(
      (_) => (
        200,
        {
          'data': [
            _favorite(_routeA, '2026-11-10T10:00:00.000000Z'),
            _favorite(_routeB, '2026-11-11T10:00:00.000000Z'),
          ],
          'included': [
            _route(_routeA, '400', 'Heredia – San José'),
            _route(_routeB, 'PV-RF', 'Puerto Viejo'),
            _company1,
          ],
        },
      ),
    );

    final favorites = await h.service.fetchFavorites();

    final request = h.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, endsWith('/ops/favorites'));
    expect(request.url.query, isEmpty);
    expect(request.headers['Authorization'], 'Bearer tok-123');

    expect([for (final f in favorites) f.routeId], [_routeB, _routeA]);
    final heredia = favorites.last;
    expect(heredia.route.code, '400');
    expect(heredia.route.name, 'Heredia – San José');
    expect(heredia.companyName, 'TUASA');
    expect(heredia.label, 'Trabajo');
    expect(heredia.savedAt, DateTime.utc(2026, 11, 10, 10));
  });

  test('a favorite whose route is not included keeps its route id', () async {
    final h = _Harness(
      (_) => (
        200,
        {
          'data': [_favorite(_routeA, '2026-11-10T10:00:00.000000Z')],
        },
      ),
    );

    final favorite = (await h.service.fetchFavorites()).single;
    expect(favorite.routeId, _routeA);
    expect(favorite.route.name, isEmpty);
  });

  test('AC4 · no favorites: empty list', () async {
    final h = _Harness((_) => (200, {'data': <Object>[]}));
    expect(await h.service.fetchFavorites(), isEmpty);
  });

  test('AC5 · POST ops/favorites with {route_id} only', () async {
    final h = _Harness(
      (_) => (
        201,
        {
          'data': _favorite(_routeA, '2026-11-11T10:00:00.000000Z'),
          'included': [_route(_routeA, '400', 'Heredia – San José')],
        },
      ),
    );

    final saved = await h.service.addFavorite(_routeA);

    final request = h.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, endsWith('/ops/favorites'));
    expect(jsonDecode(request.body), {'route_id': _routeA});
    expect(request.headers['Authorization'], 'Bearer tok-123');
    expect(saved!.route.code, '400');
  });

  test('409 (already a favorite) is not an error', () async {
    final h = _Harness(
      (_) => (
        409,
        {
          'errors': [
            {'status': '409', 'title': 'Conflict'},
          ],
        },
      ),
    );
    expect(await h.service.addFavorite(_routeA), isNull);
  });

  test('AC6 · DELETE ops/favorites/{route_id}; 404 (already removed) is '
      'not an error', () async {
    final h = _Harness((_) => (204, null));
    await h.service.removeFavorite(_routeA);
    expect(h.requests.single.method, 'DELETE');
    expect(h.requests.single.url.path, endsWith('/ops/favorites/$_routeA'));

    final gone = _Harness((_) => (404, null));
    await gone.service.removeFavorite(_routeA);
  });

  test('errors become ApiException (401, 422, 429, 5xx)', () async {
    for (final (status, type) in [
      (401, ApiErrorType.unauthorized),
      (422, ApiErrorType.validation),
      (429, ApiErrorType.tooManyRequests),
      (503, ApiErrorType.serviceUnavailable),
    ]) {
      final h = _Harness((_) => (status, null));
      await expectLater(
        h.service.addFavorite(_routeA),
        throwsA(isA<ApiException>().having((e) => e.type, 'type', type)),
      );
    }
  });
}
