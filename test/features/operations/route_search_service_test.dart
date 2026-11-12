import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartbus_drivers/core/network/api_client.dart';
import 'package:smartbus_drivers/core/network/api_exception.dart';
import 'package:smartbus_drivers/core/storage/secure_session_store.dart';
import 'package:smartbus_drivers/features/operations/models/operations_models.dart';
import 'package:smartbus_drivers/features/operations/services/operations_service.dart';

import 'operations_fixtures.dart';

/// OperationsService against a fake Gateway that serves the catalogue in
/// [pages] (one JSON:API document per `page[number]`).
class _Harness {
  _Harness(this.pages, {this.failFirst = false}) {
    service = OperationsService(
      client: ApiClient(
        sessionStore: SecureSessionStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (failFirst && requests.length == 1) {
            return _json({'message': 'Service Unavailable'}, 503);
          }
          final number = int.parse(
            request.url.queryParameters['page[number]'] ?? '1',
          );
          return _json(pages[number - 1], 200);
        }),
      ),
    );
  }

  final List<Map<String, dynamic>> pages;
  final bool failFirst;
  final List<http.Request> requests = [];
  late final OperationsService service;

  static http.Response _json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/vnd.api+json; charset=utf-8'},
  );
}

Map<String, dynamic> _route(
  String id,
  String code,
  String name, [
  List<String> patterns = const [],
]) => searchRouteResource(id: id, code: code, name: name, patternIds: patterns);

/// Catalogue: company + directions to Heredia, San José and Pérez Zeledón.
Map<String, dynamic> _page(
  List<Map<String, dynamic>> routes, {
  int current = 1,
  int last = 1,
}) => {
  ...searchDocument(routes, currentPage: current, lastPage: last),
  'included': [
    ...searchIncluded(),
    {
      'id': 'p-3',
      'type': 'route-patterns',
      'attributes': {'code': '700-1', 'headsign': 'Pérez Zeledón'},
    },
  ],
};

final _heredia = _route('r-400', '400', 'Heredia – San José', ['p-1', 'p-2']);
final _barva = _route('r-401', '401', 'Heredia – Barva', ['p-1']);
final _pena = _route('r-pb', 'PB-1', 'Peña Blanca');
final _sur = _route('r-700', '700', 'Interurbano Sur', ['p-3']);
final _code40 = _route('r-40', '40', 'Ruta corta');

List<String> _ids(RoutePage page) => [for (final r in page.routes) r.id];

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('downloads every page of the public catalogue, with company and '
      'directions, without a token', () async {
    final h = _Harness([
      _page([_heredia], current: 1, last: 2),
      _page([_barva], current: 2, last: 2),
    ]);

    await h.service.searchRoutes('heredia');

    expect(h.requests, hasLength(2));
    for (final (i, request) in h.requests.indexed) {
      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/ops/routes'));
      final query = request.url.queryParameters;
      expect(query['include'], 'company,patterns');
      expect(query['sort'], 'code');
      expect(query['page[size]'], '100');
      expect(query['page[number]'], '${i + 1}');
      expect(request.headers.containsKey('Authorization'), isFalse);
    }
  });

  group('with or without accents, any case', () {
    late _Harness h;
    setUp(
      () => h = _Harness([
        _page([_heredia, _barva, _pena, _sur]),
      ]),
    );

    test('"san jose" and "SAN JOSÉ" find "San José"', () async {
      expect(_ids(await h.service.searchRoutes('san jose')), ['r-400']);
      expect(_ids(await h.service.searchRoutes('SAN JOSÉ')), ['r-400']);
    });

    test('"pena" and "peña" find "Peña Blanca"', () async {
      expect(_ids(await h.service.searchRoutes('pena')), ['r-pb']);
      expect(_ids(await h.service.searchRoutes('Peña')), ['r-pb']);
    });

    test(
      '"heredía" (accent where there is none) still finds Heredia',
      () async {
        expect(_ids(await h.service.searchRoutes('heredía')), [
          'r-400',
          'r-401',
        ]);
      },
    );

    test('by number, partial and any case ("pb" → PB-1)', () async {
      expect(_ids(await h.service.searchRoutes('pb')), ['r-pb']);
    });

    test('by destination (headsign), with or without accents', () async {
      expect(_ids(await h.service.searchRoutes('perez zeledon')), ['r-700']);
      expect(_ids(await h.service.searchRoutes('Pérez')), ['r-700']);
    });

    test('no match: empty page', () async {
      final page = await h.service.searchRoutes('cartago');
      expect(page.routes, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('company and destinations come with each result', () async {
      final route = (await h.service.searchRoutes('san jose')).routes.single;
      expect(route.name, 'Heredia – San José');
      expect(route.companyName, 'TUASA');
      expect(route.destinations, ['Heredia', 'San José']);
    });
  });

  test(
    'order: exact number, then number or name, then destination only',
    () async {
      final onlyDestination = _route('r-900', '900', 'Expreso', ['p-1']);
      final h = _Harness([
        _page([_barva, onlyDestination, _heredia, _code40]),
      ]);

      // "40": exact code 40, then 400 / 401 (code contains "40").
      expect(_ids(await h.service.searchRoutes('40')), [
        'r-40',
        'r-400',
        'r-401',
      ]);
      // "heredia": by name (400, 401), then by destination only (900).
      expect(_ids(await h.service.searchRoutes('heredia')), [
        'r-400',
        'r-401',
        'r-900',
      ]);
    },
  );

  test('pages of ${OperationsService.searchPageSize} results', () async {
    final many = [
      for (var i = 0; i < 25; i++)
        _route('r-$i', 'H-${i.toString().padLeft(2, '0')}', 'Heredia $i'),
    ];
    final h = _Harness([_page(many)]);

    final first = await h.service.searchRoutes('heredia');
    final second = await h.service.searchRoutes('heredia', page: 2);

    expect(first.routes, hasLength(20));
    expect(first.hasMore, isTrue);
    expect(second.routes, hasLength(5));
    expect(second.hasMore, isFalse);
    expect(second.routes.first.code, 'H-20');
  });

  test('the catalogue is downloaded once for every search', () async {
    final h = _Harness([
      _page([_heredia, _barva]),
    ]);

    await Future.wait([
      h.service.searchRoutes('heredia'),
      h.service.searchRoutes('barva'),
    ]);
    await h.service.searchRoutes('san jose');

    expect(h.requests, hasLength(1));
  });

  test('a failed download is not kept: the next search tries again', () async {
    final h = _Harness([
      _page([_heredia]),
    ], failFirst: true);

    await expectLater(
      h.service.searchRoutes('heredia'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.type,
          'type',
          ApiErrorType.serviceUnavailable,
        ),
      ),
    );
    expect(_ids(await h.service.searchRoutes('heredia')), ['r-400']);
    expect(h.requests, hasLength(2));
  });

  test('without included resources only code and name are known', () {
    final route = TransitRoute.fromJsonApi(routeResource());

    expect(route.code, 'PV-RF');
    expect(route.companyName, isNull);
    expect(route.destinations, isEmpty);
  });

  test('foldForSearch: lower case, no accents, same length', () {
    const text = 'JOSÉ Peña Ñandú Güell';
    expect(foldForSearch(text), 'jose pena nandu guell');
    expect(foldForSearch(text).length, text.length);
  });
}
