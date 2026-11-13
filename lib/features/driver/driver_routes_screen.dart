import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/secure_session_store.dart';
import '../../core/theme.dart';
import '../../widgets/driver_bottom_nav.dart';
import '../../widgets/smartbus_header.dart';
import '../operations/models/operations_models.dart';
import '../operations/services/operations_service.dart';
import '../trip_tracking/models/trip_tracking.dart';
import '../trip_tracking/services/active_trip_tracking.dart';
import 'trip_screen.dart';
import 'widgets/trip_status_badge.dart';

/// "Mis rutas" tab: the **history** of trips assigned to the driver, any day,
/// the most recent first (`GET ops/driver/trips?sort=-scheduled_departure_at`),
/// grouped by day.
///
/// Each trip shows its route, destination, bus, the scheduled and actual
/// times, and its status (the same badge as Inicio and Recorrido). Chips
/// filter by status (server side, `filter[status]`); "Cargar más" asks the
/// next page. A trip in progress can be continued from here.
///
/// A 401 clears the session and goes to Login.
class DriverRoutesScreen extends StatefulWidget {
  const DriverRoutesScreen({
    super.key,
    this.operations,
    this.sessionStore,
    this.clock = DateTime.now,
  });

  final OperationsService? operations;

  /// Cleared when the Gateway answers 401.
  final SecureSessionStore? sessionStore;

  /// "Today", for the "Hoy" / "Ayer" day labels (tests fix it).
  final DateTime Function() clock;

  /// No trips at all (no filter).
  static const emptyMessage = 'Aún no tienes viajes asignados.';

  @override
  State<DriverRoutesScreen> createState() => _DriverRoutesScreenState();
}

class _DriverRoutesScreenState extends State<DriverRoutesScreen> {
  late final OperationsService _operations =
      widget.operations ?? OperationsService();
  late final SecureSessionStore _session =
      widget.sessionStore ?? SecureSessionStore();

  /// `null` = every status.
  TripStatus? _filter;

  List<DriverTrip>? _trips;
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// Bumped on every new list (filter change, refresh): an older answer that
  /// arrives late is ignored.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// First page of the current filter.
  Future<void> _reload() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _operations.driverTripHistory(status: _filter);
      if (!mounted || seq != _seq) return;
      setState(() {
        _trips = page.trips;
        _page = 1;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      if (e.type == ApiErrorType.unauthorized) {
        await _onSessionExpired(e);
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  /// "Cargar más": the next page, appended. A failure keeps the list.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    try {
      final page = await _operations.driverTripHistory(
        page: _page + 1,
        status: _filter,
      );
      if (!mounted || seq != _seq) return;
      final known = {for (final trip in _trips!) trip.id};
      setState(() {
        // A trip may move between pages while paging: never twice.
        _trips = [
          ..._trips!,
          ...page.trips.where((trip) => !known.contains(trip.id)),
        ];
        _page++;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      if (e.type == ApiErrorType.unauthorized) {
        await _onSessionExpired(e);
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: SmartBusColors.error,
            action: SnackBarAction(
              label: 'Reintentar',
              textColor: SmartBusColors.blanco,
              onPressed: _loadMore,
            ),
          ),
        );
    } finally {
      if (mounted && seq == _seq) setState(() => _loadingMore = false);
    }
  }

  void _setFilter(TripStatus? status) {
    if (status == _filter) return;
    setState(() {
      _filter = status;
      _trips = null;
    });
    _reload();
  }

  Future<void> _onSessionExpired(ApiException e) async {
    ActiveTripTracking.stop(); // the GPS would get 401 too
    await _session.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: SmartBusColors.error,
      ),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  void _continue(DriverTrip trip) {
    Navigator.pushReplacementNamed(
      context,
      '/driver/trip',
      arguments: TripScreenArgs(trip: trip, autoStart: true),
    );
  }

  void _onTabTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/driver/home');
      case 1:
        return; // already on Mis rutas
      case 2:
        Navigator.pushReplacementNamed(context, '/driver/trip');
      case 3:
        Navigator.pushReplacementNamed(context, '/driver/account');
    }
  }

  // --- UI ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SmartBusColors.blanco,
      bottomNavigationBar: DriverBottomNav(currentIndex: 1, onTap: _onTabTap),
      body: Column(
        children: [
          const SmartBusHeader(
            title: 'Mis Rutas',
            subtitle: 'Historial de viajes asignados',
            type: SmartBusUserType.driver,
          ),
          _FilterChips(
            selected: _filter,
            enabled: !_loading,
            onSelected: _setFilter,
          ),
          Expanded(
            child: RefreshIndicator(onRefresh: _reload, child: _body()),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final trips = _trips;
    if (_loading && trips == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('history-loading')),
      );
    }
    if (_error != null && (trips == null || trips.isEmpty)) {
      return _CenteredMessage(
        icon: Icons.cloud_off,
        title: 'No se pudo cargar el historial',
        message: _error!,
        actionLabel: 'Reintentar',
        onAction: _reload,
      );
    }
    if (trips == null || trips.isEmpty) {
      return _CenteredMessage(
        icon: Icons.history,
        title: _filter == null
            ? DriverRoutesScreen.emptyMessage
            : 'No hay viajes ${_filterLabel(_filter!).toLowerCase()}.',
        message: _filter == null
            ? 'Los viajes que te asigne tu empresa aparecerán aquí.'
            : 'Prueba con otro estado.',
      );
    }

    final today = widget.clock();
    final items = <Widget>[];
    String? day;
    for (final trip in trips) {
      final label = dayLabel(trip.scheduledDepartureAt, today);
      if (label != day) {
        day = label;
        items.add(_DayHeader(label));
      }
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _HistoryCard(
            trip: trip,
            onContinue: trip.status == TripStatus.inProgress
                ? () => _continue(trip)
                : null,
          ),
        ),
      );
    }
    if (_hasMore) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: _loadingMore
                ? const CircularProgressIndicator(key: Key('history-more'))
                : OutlinedButton.icon(
                    key: const Key('load-more'),
                    onPressed: _loadMore,
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Cargar más'),
                  ),
          ),
        ),
      );
    }
    return ListView(
      key: const Key('trip-history'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: items,
    );
  }
}

/// Label of a status filter chip.
String _filterLabel(TripStatus status) => switch (status) {
  TripStatus.scheduled => 'Programados',
  TripStatus.inProgress => 'En curso',
  TripStatus.completed => 'Finalizados',
  TripStatus.cancelled => 'Cancelados',
  TripStatus.unknown => 'Otros',
};

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// "Hoy", "Ayer", "Mañana" or "mié 11 nov" (+ the year when it is not the
/// current one), in local time.
String dayLabel(DateTime? at, DateTime today) {
  if (at == null) return 'Sin fecha';
  final local = at.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final now = DateTime(today.year, today.month, today.day);
  final diff = day.difference(now).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == -1) return 'Ayer';
  if (diff == 1) return 'Mañana';
  final label =
      '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}';
  return local.year == today.year ? label : '$label ${local.year}';
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final TripStatus? selected;
  final bool enabled;
  final ValueChanged<TripStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    const statuses = [
      TripStatus.scheduled,
      TripStatus.inProgress,
      TripStatus.completed,
      TripStatus.cancelled,
    ];
    return SingleChildScrollView(
      key: const Key('history-filters'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          _chip('Todos', null),
          for (final status in statuses) _chip(_filterLabel(status), status),
        ],
      ),
    );
  }

  Widget _chip(String label, TripStatus? status) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: Key('filter-${status?.name ?? 'all'}'),
        label: Text(label),
        selected: selected == status,
        onSelected: enabled ? (_) => onSelected(status) : null,
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// A trip of the history: route, status, destination, bus, scheduled and
/// actual times; "Continuar recorrido" when it is in progress.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.trip, required this.onContinue});

  final DriverTrip trip;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(color: Colors.grey.shade700, fontSize: 13);
    final departure = trip.scheduledDepartureAt;
    final arrival = trip.scheduledArrivalAt;
    final actualDeparture = trip.actualDepartureAt;
    final actualArrival = trip.actualArrivalAt;

    return Container(
      key: Key('history-trip-${trip.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SmartBusColors.grisClaro,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.directions_bus_filled,
                  color: SmartBusColors.azulPrincipal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  trip.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SmartBusColors.grisOscuro,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TripStatusBadge.forStatus(trip.status),
            ],
          ),
          if (trip.headsign != null) ...[
            const SizedBox(height: 4),
            Text('Hacia ${trip.headsign}', style: secondary),
          ],
          if (trip.busLabel != null) ...[
            const SizedBox(height: 2),
            Text(trip.busLabel!, style: secondary),
          ],
          if (departure != null) ...[
            const SizedBox(height: 8),
            _TimeRow(
              icon: Icons.schedule,
              label: 'Horario',
              value: arrival == null
                  ? formatHour(departure)
                  : '${formatHour(departure)} → ${formatHour(arrival)}',
            ),
          ],
          if (actualDeparture != null) ...[
            const SizedBox(height: 4),
            _TimeRow(
              icon: Icons.play_circle_outline,
              label: 'Real',
              value: actualArrival == null
                  ? 'Salió ${formatHour(actualDeparture)}'
                  : '${formatHour(actualDeparture)} → '
                        '${formatHour(actualArrival)}'
                        '${_duration(actualDeparture, actualArrival)}',
            ),
          ],
          if (trip.status == TripStatus.scheduled && actualDeparture == null)
            ..._note('Pendiente de iniciar', Colors.grey.shade600),
          if (trip.status == TripStatus.cancelled)
            ..._note('Este viaje fue cancelado', SmartBusColors.error),
          if (onContinue != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('continue-${trip.id}'),
                onPressed: onContinue,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Continuar recorrido'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static List<Widget> _note(String text, Color color) => [
    const SizedBox(height: 6),
    Text(text, style: TextStyle(color: color, fontSize: 12)),
  ];

  /// " · 1 h 02 min" between [from] and [to] (nothing if negative).
  static String _duration(DateTime from, DateTime to) {
    final minutes = to.difference(from).inMinutes;
    if (minutes < 0) return '';
    if (minutes < 60) return ' · $minutes min';
    final rest = (minutes % 60).toString().padLeft(2, '0');
    return ' · ${minutes ~/ 60} h $rest min';
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // Scrollable so it can be pulled to refresh.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 56, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
