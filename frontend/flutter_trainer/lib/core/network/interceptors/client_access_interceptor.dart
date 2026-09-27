import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reports a member whose data the server just refused with 404.
///
/// A member can end the coaching link from the member app at any moment.
/// The server then answers every member-scoped trainer endpoint
/// (`/trainer/clients/{id}/…`) with 404 (#2281), but the roster this
/// console is showing still lists that member until its next poll. Until
/// then an open detail, chat thread or report would sit on stale data or
/// an unexplained error.
///
/// This interceptor turns such a 404 into a signal so the roster can be
/// revalidated right away. Once the roster drops the member, every page
/// that selects by id (member detail, messages, reports) falls back to its
/// existing not-found/empty state.
///
/// A 404 here is not proof the link ended — a deleted memo or an unknown
/// photo also answers 404. Reporting it anyway is safe: the roster read
/// decides, and it is a single roster-only refresh (the member's own data
/// streams are not re-read, so a persistent 404 cannot loop).
class ClientAccessInterceptor extends Interceptor {
  /// Calls [onAccessLost] with the member id of a refused member request.
  ClientAccessInterceptor(this.onAccessLost);

  /// Receives the member id taken from the request path.
  final void Function(String clientId) onAccessLost;

  /// Link-management endpoints that address the link itself rather than the
  /// member's data. Their 404/409 already mean "this link is gone" and the
  /// screens that call them refresh the roster on their own.
  static const Set<String> _linkEndpoints = <String>{'registration', 'status'};

  /// The member id when [path] is a member-scoped trainer data endpoint
  /// (`…/trainer/clients/{id}/{resource}…`), otherwise `null`.
  ///
  /// The bare `/trainer/clients/{id}` (ending the link) and the roster
  /// itself are not data endpoints and yield `null`.
  static String? scopedClientId(String path) {
    final List<String> segments = Uri.parse(
      path,
    ).pathSegments.where((String s) => s.isNotEmpty).toList();
    for (int i = 0; i + 3 < segments.length; i++) {
      if (segments[i] != 'trainer' || segments[i + 1] != 'clients') continue;
      if (_linkEndpoints.contains(segments[i + 3])) return null;
      final String id = segments[i + 2];
      return id.isEmpty ? null : id;
    }
    return null;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 404) {
      final String? id = scopedClientId(err.requestOptions.uri.path);
      if (id != null) onAccessLost(id);
    }
    handler.next(err);
  }
}

/// Broadcasts member ids reported by [ClientAccessInterceptor].
class ClientAccessLostSignal {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// Member ids whose data request was just refused.
  Stream<String> get stream => _controller.stream;

  /// Reports [clientId]. Ignored after [close].
  void report(String clientId) {
    if (!_controller.isClosed) _controller.add(clientId);
  }

  /// Releases the stream.
  Future<void> close() => _controller.close();
}

/// The app-wide [ClientAccessLostSignal] shared by `dioProvider` (producer)
/// and the client repository (consumer).
final clientAccessLostProvider = Provider<ClientAccessLostSignal>((ref) {
  final ClientAccessLostSignal signal = ClientAccessLostSignal();
  ref.onDispose(signal.close);
  return signal;
}, name: 'clientAccessLost');
