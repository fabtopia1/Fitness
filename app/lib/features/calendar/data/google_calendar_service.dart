import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/error/failure_mapper.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/features/calendar/domain/calendar_entities.dart';
import 'package:uuid/uuid.dart';

/// Google Calendar, read-only.
///
/// SCOPE CHOICE: `calendar.readonly` only. Writing to a user's real calendar
/// is a far heavier consent prompt and a far worse failure mode — a sync bug
/// that deletes a work meeting is unrecoverable. LifeDNA's own events live in
/// its own store and are shown alongside; they are never pushed into Google.
///
/// Requires an OAuth client id supplied at build time. Without one the module
/// stays locked and the UI says exactly what is missing rather than failing
/// with an opaque error.
class GoogleCalendarService {
  GoogleCalendarService({GoogleSignIn? signIn, Uuid uuid = const Uuid()})
    : _uuid = uuid,
      _signIn =
          signIn ??
          (Env.calendarConfigured
              ? GoogleSignIn(
                  scopes: const [gcal.CalendarApi.calendarReadonlyScope],
                  clientId: Env.googleCalendarClientId,
                )
              : null);

  final GoogleSignIn? _signIn;
  final Uuid _uuid;

  bool get isConfigured => Env.calendarConfigured && _signIn != null;

  Future<bool> get isConnected async {
    final signIn = _signIn;
    if (signIn == null) return false;
    return signIn.isSignedIn();
  }

  /// Prompts for consent. Returns the connected account email.
  Future<Result<String>> connect() async {
    final signIn = _signIn;
    if (signIn == null) {
      return const Err(ServerFailure('calendar_not_configured'));
    }
    try {
      final account = await signIn.signIn();
      if (account == null) {
        return const Err(AuthFailure('sign_in_canceled'));
      }
      return Ok(account.email);
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  Future<Result<void>> disconnect() async {
    final signIn = _signIn;
    if (signIn == null) return const Ok(null);
    try {
      await signIn.disconnect();
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  /// Fetches events in a window and maps them to the app's own model.
  ///
  /// Uses silent sign-in so a routine refresh never interrupts the user with a
  /// consent dialog they already answered.
  Future<Result<List<CalendarEvent>>> fetchEvents({
    required DateTime from,
    required DateTime to,
    int maxResults = 250,
  }) async {
    final signIn = _signIn;
    if (signIn == null) {
      return const Err(ServerFailure('calendar_not_configured'));
    }

    try {
      var account = await signIn.signInSilently();
      account ??= await signIn.signIn();
      if (account == null) {
        return const Err(AuthFailure('sign_in_canceled'));
      }

      final auth.AuthClient? client = await signIn.authenticatedClient();
      if (client == null) {
        return const Err(AuthFailure('no_google_credentials'));
      }

      try {
        final api = gcal.CalendarApi(client);
        final response = await api.events
            .list(
              'primary',
              timeMin: from.toUtc(),
              timeMax: to.toUtc(),
              singleEvents: true,
              orderBy: 'startTime',
              maxResults: maxResults,
            )
            .timeout(Env.networkTimeout);

        final events = <CalendarEvent>[];
        for (final item in response.items ?? const <gcal.Event>[]) {
          final mapped = _map(item);
          if (mapped != null) events.add(mapped);
        }
        return Ok(events);
      } finally {
        client.close();
      }
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  CalendarEvent? _map(gcal.Event event) {
    final start = event.start?.dateTime ?? _allDay(event.start?.date);
    final end =
        event.end?.dateTime ??
        _allDay(event.end?.date) ??
        start?.add(const Duration(hours: 1));
    if (start == null || end == null) return null;
    if (event.status == 'cancelled') return null;

    final providerId = event.id ?? _uuid.v4();
    return CalendarEvent(
      // Namespaced so a Google event can never collide with a LifeDNA one.
      id: 'google_$providerId',
      title: event.summary?.trim().isNotEmpty ?? false
          ? event.summary!.trim()
          : '(No title)',
      description: event.description,
      location: event.location,
      startAt: start.toUtc(),
      endAt: end.toUtc(),
      isAllDay: event.start?.date != null,
      source: EventSource.google,
      providerEventId: providerId,
      calendarId: 'primary',
      updatedAt: event.updated?.toUtc() ?? DateTime.now().toUtc(),
    );
  }

  static DateTime? _allDay(DateTime? date) =>
      date == null ? null : DateTime(date.year, date.month, date.day);

  /// The exact setup step a developer must complete to enable this module.
  static const String setupInstructions =
      'Google Calendar needs an OAuth client id. Create an Android OAuth '
      'client in Google Cloud Console for the app package and SHA-1, enable '
      'the Google Calendar API, then build with '
      '--dart-define=GOOGLE_CALENDAR_CLIENT_ID=<id>.';

  /// Convenience used by the sync path to stamp a local date on a fetched event.
  static String localDateOf(CalendarEvent event) =>
      Json.localDate(event.startAt.toLocal());
}
