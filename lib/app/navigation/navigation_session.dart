import 'dart:async';

import 'package:flutter/foundation.dart';

import 'navigation_context.dart';
import 'navigation_period.dart';
import 'wealth_route.dart' show madridMonth;

typedef NavigationClock = DateTime Function();
typedef NavigationLeaveGuard = Future<bool> Function();

/// Estado en memoria, propiedad de una instancia de AutofinanceApp.
/// El reloj se lee al crear la sesión y al pedir explícitamente Mes actual.
final class NavigationSession extends ChangeNotifier {
  NavigationSession({NavigationClock? clock, NavigationContext? initialContext})
    : _clock = clock ?? DateTime.now {
    _context =
        initialContext ??
        NavigationContext(
          destination: SessionDestination.status,
          period: NavigationPeriod.fromMonth(madridMonth(_clock())),
        );
    _remember(_context.period);
  }

  final NavigationClock _clock;
  late NavigationContext _context;
  final Map<int, int> _months = {};
  int _revision = 0;
  bool _disposed = false;
  NavigationContext get context => _context;
  NavigationPeriod get period => context.period;
  int? rememberedMonth(int year) {
    NavigationPeriod(
      year,
      1,
    ); // Valida también el año de una consulta de memoria.
    return _months[year];
  }

  NavigationPeriod periodForYear(int year, PeriodView view) => NavigationPeriod(
    year,
    view == PeriodView.monthly ? period.month : rememberedMonth(year) ?? 1,
  );

  Future<bool> selectPeriod(
    NavigationPeriod value, {
    NavigationLeaveGuard? guard,
  }) => setContext(context.withPeriod(value), guard: guard);

  Future<bool> selectYear(
    int year, {
    PeriodView? view,
    NavigationLeaveGuard? guard,
  }) => selectPeriod(periodForYear(year, view ?? context.view), guard: guard);

  Future<bool> changeDestination(
    SessionDestination destination, {
    PeriodView? view,
    NavigationLeaveGuard? guard,
  }) => setContext(
    NavigationContext(destination: destination, period: period, view: view),
    guard: guard,
  );

  Future<bool> previous({NavigationLeaveGuard? guard}) {
    final value = context.view == PeriodView.annual
        ? (period.year == 1
              ? null
              : periodForYear(period.year - 1, PeriodView.annual))
        : period.previous;
    return value == null
        ? Future.value(false)
        : selectPeriod(value, guard: guard);
  }

  Future<bool> next({NavigationLeaveGuard? guard}) {
    final value = context.view == PeriodView.annual
        ? (period.year == 9999
              ? null
              : periodForYear(period.year + 1, PeriodView.annual))
        : period.next;
    return value == null
        ? Future.value(false)
        : selectPeriod(value, guard: guard);
  }

  /// Consulta explícita del reloj de Madrid, sin modificar el contexto.
  NavigationPeriod currentPeriod() =>
      NavigationPeriod.fromMonth(madridMonth(_clock()));

  Future<bool> currentMonth({NavigationLeaveGuard? guard}) =>
      selectPeriod(currentPeriod(), guard: guard);

  SecondaryNavigationContext openSecondary() =>
      SecondaryNavigationContext(context);

  Future<bool> returnToOrigin(
    SecondaryNavigationContext detail, {
    NavigationLeaveGuard? guard,
  }) => setContext(detail.origin, guard: guard);

  /// Los consumidores resuelven sus borradores antes de cambiar contexto. Una
  /// respuesta tardía del guard no pisa una elección posterior de la sesión.
  Future<bool> setContext(
    NavigationContext value, {
    NavigationLeaveGuard? guard,
    bool deferNotification = false,
  }) async {
    if (_disposed) return false;
    final revision = _revision;
    if (guard != null && !await guard()) return false;
    if (_disposed || revision != _revision) return false;
    if (identical(value, _context)) return true;
    _context = value;
    _remember(value.period);
    _revision++;
    if (deferNotification) {
      final publishedRevision = _revision;
      scheduleMicrotask(() {
        if (!_disposed && publishedRevision == _revision) notifyListeners();
      });
    } else {
      notifyListeners();
    }
    return true;
  }

  void _remember(NavigationPeriod value) => _months[value.year] = value.month;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
