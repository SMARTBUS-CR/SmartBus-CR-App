/// Fare and departure timetable of a route, from the Dashboard
/// (`GET ops/routes/{id}/fares`, `GET ops/route-patterns/{id}/schedules`).
library;

/// The price of a route (`route-fares`), valid between two dates.
class RouteFare {
  const RouteFare({
    required this.amount,
    required this.currency,
    this.validFrom,
    this.validUntil,
  });

  factory RouteFare.fromJsonApi(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    return RouteFare(
      amount: _number(attributes['amount']) ?? 0,
      currency: attributes['currency']?.toString() ?? 'CRC',
      validFrom: _day(attributes['valid_from']),
      validUntil: _day(attributes['valid_until']),
    );
  }

  final double amount;

  /// ISO 4217 code (`CRC`).
  final String currency;

  /// First and last day it applies (`null` = no limit).
  final DateTime? validFrom;
  final DateTime? validUntil;

  bool appliesOn(DateTime date) => _within(date, validFrom, validUntil);

  /// "₡1.570" (colones without decimals), "₡1.570,50", "USD 2,50".
  String get label => formatMoney(amount, currency);
}

/// One weekly departure of a pattern (`route-schedules`): every
/// [dayOfWeek] at [hour]:[minute], except its suspended dates.
class RouteSchedule {
  const RouteSchedule({
    required this.dayOfWeek,
    required this.hour,
    required this.minute,
    this.validFrom,
    this.validUntil,
    this.suspendedDates = const [],
  });

  factory RouteSchedule.fromJsonApi(Map<String, dynamic> resource) {
    final attributes = _attributes(resource);
    final time = (attributes['departure_time']?.toString() ?? '').split(':');
    final suspended = attributes['suspended_dates'];
    return RouteSchedule(
      dayOfWeek: _number(attributes['day_of_week'])?.toInt() ?? -1,
      hour: int.tryParse(time.isNotEmpty ? time[0] : '') ?? 0,
      minute: int.tryParse(time.length > 1 ? time[1] : '') ?? 0,
      validFrom: _day(attributes['valid_from']),
      validUntil: _day(attributes['valid_until']),
      suspendedDates: [
        if (suspended is List)
          for (final value in suspended) ?_day(value),
      ],
    );
  }

  /// 0 = Sunday … 6 = Saturday (Carbon `dayOfWeek`, as the Dashboard stores it).
  final int dayOfWeek;
  final int hour;
  final int minute;
  final DateTime? validFrom;
  final DateTime? validUntil;

  /// Days this departure does not run (holidays, suspensions).
  final List<DateTime> suspendedDates;

  /// "06:00".
  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Minutes since midnight, to sort and compare.
  int get minutesOfDay => hour * 60 + minute;

  /// Whether this departure runs on [date] (its local day).
  bool runsOn(DateTime date) {
    if (date.weekday % 7 != dayOfWeek) return false; // Dart: Monday = 1 … 7
    if (!_within(date, validFrom, validUntil)) return false;
    return !suspendedDates.any((day) => _sameDay(day, date));
  }
}

/// The departures of [schedules] that run on [date], earliest first.
List<RouteSchedule> departuresOn(List<RouteSchedule> schedules, DateTime date) {
  final today = schedules.where((s) => s.runsOn(date)).toList()
    ..sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
  return today;
}

/// The fare that applies on [date] (the latest one when several do).
RouteFare? fareOn(List<RouteFare> fares, DateTime date) {
  final valid = fares.where((fare) => fare.appliesOn(date)).toList();
  if (valid.isEmpty) return null;
  valid.sort(
    (a, b) =>
        (a.validFrom ?? DateTime(0)).compareTo(b.validFrom ?? DateTime(0)),
  );
  return valid.last;
}

/// "₡1.570" — colones with a dot every three digits and no decimals when
/// they are zero; other currencies with their code ("USD 2,50").
String formatMoney(double amount, String currency) {
  final cents = (amount * 100).round();
  final whole = cents ~/ 100;
  final fraction = cents % 100;
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  final number = fraction == 0
      ? grouped.toString()
      : '$grouped,${fraction.toString().padLeft(2, '0')}';
  return currency == 'CRC' ? '₡$number' : '$currency $number';
}

// --- helpers -------------------------------------------------------------------

Map<String, dynamic> _attributes(Map<String, dynamic> resource) {
  final attributes = resource['attributes'];
  return attributes is Map ? Map<String, dynamic>.from(attributes) : const {};
}

double? _number(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s),
  _ => null,
};

/// "2026-11-12" → that local day (no time).
DateTime? _day(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _within(DateTime date, DateTime? from, DateTime? until) {
  final day = DateTime(date.year, date.month, date.day);
  if (from != null && day.isBefore(from)) return false;
  if (until != null && day.isAfter(until)) return false;
  return true;
}
