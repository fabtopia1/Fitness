import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device currently has a usable network path.
///
/// This is advisory only. Nothing in the app blocks on it: writes always
/// commit locally, and the sync engine simply drains sooner when this reports
/// connectivity. Treating it as authoritative would be a mistake — a captive
/// portal reports "connected" and drops every request.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> get isOnline async =>
      _isOnline(await _connectivity.checkConnectivity());

  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty &&
      !results.every((r) => r == ConnectivityResult.none);
}
