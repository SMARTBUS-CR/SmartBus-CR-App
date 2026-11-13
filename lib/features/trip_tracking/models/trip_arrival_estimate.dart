import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Real-time or scheduled arrival estimate for a stop in a trip.
@immutable
class TripArrivalEstimate {
  const TripArrivalEstimate({
    required this.occurrenceId,
    required this.stopId,
    required this.stopSequence,
    this.etaSeconds,
    this.arrivalAt,
    required this.method,
  });

  final String occurrenceId;
  final String stopId;
  final int stopSequence;
  final int? etaSeconds;
  final DateTime? arrivalAt;

  /// Calculation method: 'ml', 'fallback', 'scheduled_reference', 'unavailable'.
  final String method;

  factory TripArrivalEstimate.fromJson(Map<String, dynamic> json) {
    final etaRaw = json['eta_seconds'] ?? json['etaSeconds'];
    final arrivalRaw = json['arrival_at'] ?? json['arrivalAt'];
    final seqRaw = json['stop_sequence'] ?? json['stopSequence'];

    return TripArrivalEstimate(
      occurrenceId: (json['occurrence_id'] ??
              json['stop_occurrence_id'] ??
              json['occurrenceId'])
          ?.toString() ??
          '',
      stopId: (json['stop_id'] ?? json['stopId'])?.toString() ?? '',
      stopSequence: switch (seqRaw) {
        num n => n.toInt(),
        String s => int.tryParse(s) ?? 0,
        _ => 0,
      },
      etaSeconds: switch (etaRaw) {
        num n => n.toInt(),
        String s => int.tryParse(s),
        _ => null,
      },
      arrivalAt: arrivalRaw != null
          ? DateTime.tryParse(arrivalRaw.toString())?.toLocal()
          : null,
      method: (json['method'] ?? 'unavailable').toString(),
    );
  }

  /// Estimated arrival in whole minutes, rounded to nearest.
  int? get etaMinutes =>
      etaSeconds != null ? (etaSeconds! / 60).round() : null;

  /// True when the estimate is based on real-time data (ML model or speed/distance fallback).
  bool get isLive => method == 'ml' || method == 'fallback';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripArrivalEstimate &&
          runtimeType == other.runtimeType &&
          occurrenceId == other.occurrenceId &&
          stopId == other.stopId &&
          stopSequence == other.stopSequence &&
          etaSeconds == other.etaSeconds &&
          arrivalAt == other.arrivalAt &&
          method == other.method;

  @override
  int get hashCode => Object.hash(
    occurrenceId,
    stopId,
    stopSequence,
    etaSeconds,
    arrivalAt,
    method,
  );

  @override
  String toString() =>
      'TripArrivalEstimate(stopId: $stopId, etaSeconds: $etaSeconds, etaMinutes: $etaMinutes, method: $method)';
}

/// Parses an arrivals payload from a realtime event or API response into a
/// map indexed by both [TripArrivalEstimate.stopId] and [TripArrivalEstimate.occurrenceId].
Map<String, TripArrivalEstimate> parseArrivals(dynamic data) {
  if (data == null) return const {};
  dynamic raw = data;
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return const {};
    }
  }

  List? list;
  if (raw is List) {
    list = raw;
  } else if (raw is Map) {
    if (raw['arrivals'] is List) {
      list = raw['arrivals'] as List;
    } else if (raw['data'] is Map &&
        raw['data']['attributes'] is Map &&
        raw['data']['attributes']['arrivals'] is List) {
      list = raw['data']['attributes']['arrivals'] as List;
    } else if (raw['data'] is List) {
      list = raw['data'] as List;
    }
  }

  if (list == null) return const {};

  final result = <String, TripArrivalEstimate>{};
  for (final item in list) {
    if (item is Map) {
      final estimate = TripArrivalEstimate.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (estimate.stopId.isNotEmpty) {
        result[estimate.stopId] = estimate;
      }
      if (estimate.occurrenceId.isNotEmpty) {
        result[estimate.occurrenceId] = estimate;
      }
    }
  }
  return result;
}
