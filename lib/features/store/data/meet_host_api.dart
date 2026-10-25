// File: lib/features/store/data/meet_host_api.dart
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';

/// Host controls for a Virtual Meet, and the "who attended" report for meets
/// and live streams. Backend: src/FanittStore/controllers/meetHost.controller.js
class MeetHostApi {
  const MeetHostApi._();

  static ApiClient get _api => sl<ApiClient>();

  /// Mutes one person's mic ([video] = turns their camera off), or everyone's
  /// when [identity] is null. Returns the server's message.
  static Future<String> mute(String meetId, {String? identity, bool video = false}) async {
    final res = await _api.post(
      '/store/meets/$meetId/host/mute',
      data: {if (identity != null) 'identity': identity, 'kind': video ? 'video' : 'audio'},
      parser: (d) => d,
    );
    return res.message;
  }

  static Future<String> remove(String meetId, String identity) async {
    final res = await _api.post('/store/meets/$meetId/host/remove', data: {'identity': identity}, parser: (d) => d);
    return res.message;
  }

  static Future<bool> setLocked(String meetId, bool locked) async {
    final res = await _api.post('/store/meets/$meetId/host/lock', data: {'locked': locked}, parser: (d) => J.boolean(J.asMap(d), 'locked'));
    return res.data;
  }

  /// Whether the meeting is locked right now.
  static Future<bool> isLocked(String meetId) async {
    final res = await _api.get('/store/meets/$meetId/host/participants', parser: (d) => J.boolean(J.asMap(d), 'locked'));
    return res.data;
  }

  static Future<AttendanceReport> meetAttendance(String meetId) async =>
      (await _api.get('/store/meets/$meetId/attendance', parser: (d) => AttendanceReport.fromJson(J.asMap(d)))).data;

  static Future<AttendanceReport> liveAttendance(String liveId) async =>
      (await _api.get('/store/me/lives/$liveId/attendance', parser: (d) => AttendanceReport.fromJson(J.asMap(d)))).data;

  /// The host's past live sessions (ended, cancelled or missed), newest first.
  static Future<Paged<PastSession>> sessionHistory(int page) async {
    final res = await _api.get(
      '/sessions/mine/history',
      query: {'page': page, 'limit': 20},
      parser: (d) {
        final m = J.asMap(d);
        return Paged<PastSession>(
          items: J.list(m, 'sessions', PastSession.fromJson),
          page: J.integer(m, 'page', page),
          pages: J.integer(m, 'pages'),
          total: J.integer(m, 'total'),
        );
      },
    );
    return res.data;
  }
}

/// One row of the host's session history.
class PastSession {
  const PastSession({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.isFree,
    required this.price,
    required this.durationMinutes,
    required this.bookedCount,
    required this.attended,
    required this.watchedSeconds,
    required this.status,
    this.scheduledAt,
  });

  factory PastSession.fromJson(Map<String, dynamic> json) => PastSession(
    id: J.id(json),
    title: J.str(json, 'title'),
    coverUrl: J.str(json, 'coverImageUrl'),
    isFree: J.str(json, 'type') == 'free',
    price: J.integer(json, 'price'),
    durationMinutes: J.integer(json, 'durationMinutes'),
    bookedCount: J.integer(json, 'bookedCount'),
    attended: J.integer(json, 'attended'),
    watchedSeconds: J.integer(json, 'watchedSeconds'),
    status: J.str(json, 'status', 'ended'),
    scheduledAt: J.date(json, 'scheduledAt'),
  );

  final String id;
  final String title;
  final String coverUrl;
  final bool isFree;
  final int price;
  final int durationMinutes;
  final int bookedCount;
  final int attended;

  /// Total time everyone stayed, in seconds.
  final int watchedSeconds;

  /// 'ended' | 'cancelled' | 'missed' (time passed, never started).
  final String status;
  final DateTime? scheduledAt;

  int get averageSeconds => attended == 0 ? 0 : watchedSeconds ~/ attended;
}

class AttendanceReport {
  const AttendanceReport({required this.totalPeople, required this.inRoomNow, required this.averageSeconds, required this.totalSeconds, required this.booked, required this.people});

  factory AttendanceReport.fromJson(Map<String, dynamic> json) => AttendanceReport(
    totalPeople: J.integer(json, 'totalPeople'),
    inRoomNow: J.integer(json, 'inRoomNow'),
    averageSeconds: J.integer(json, 'averageSeconds'),
    totalSeconds: J.integer(json, 'totalSeconds'),
    booked: J.integerOrNull(json, 'booked'),
    people: J.list(json, 'people', AttendancePerson.fromJson),
  );

  final int totalPeople;
  final int inRoomNow;
  final int averageSeconds;
  final int totalSeconds;

  /// Meets only: how many people booked.
  final int? booked;
  final List<AttendancePerson> people;
}

class AttendancePerson {
  const AttendancePerson({required this.userId, required this.name, required this.avatarUrl, required this.visits, required this.watchedSeconds, required this.inRoomNow, this.firstJoinedAt, this.lastSeenAt});

  factory AttendancePerson.fromJson(Map<String, dynamic> json) => AttendancePerson(
    userId: J.str(json, 'userId'),
    name: J.str(json, 'name', 'Guest'),
    avatarUrl: J.str(json, 'avatarUrl'),
    visits: J.integer(json, 'visits'),
    watchedSeconds: J.integer(json, 'watchedSeconds'),
    inRoomNow: J.boolean(json, 'inRoomNow'),
    firstJoinedAt: J.date(json, 'firstJoinedAt'),
    lastSeenAt: J.date(json, 'lastSeenAt'),
  );

  final String userId;
  final String name;
  final String avatarUrl;
  final int visits;
  final int watchedSeconds;
  final bool inRoomNow;
  final DateTime? firstJoinedAt;
  final DateTime? lastSeenAt;
}

/// 75 → "1 min 15 s", 3700 → "1 h 1 min".
String watchTime(int seconds) {
  if (seconds < 60) return '$seconds s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return m > 0 ? '$h h $m min' : '$h h';
  return s > 0 && m < 10 ? '$m min $s s' : '$m min';
}