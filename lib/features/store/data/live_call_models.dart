import 'package:equatable/equatable.dart';

import '../../../core/utils/json.dart';

// Live streams and 1-to-1 calls (backend: src/FanittStore live/call). Paise.

enum LiveStatus {
  scheduled('scheduled', 'Upcoming'),
  live('live', 'Live'),
  ended('ended', 'Ended'),
  cancelled('cancelled', 'Cancelled');

  const LiveStatus(this.value, this.label);
  final String value;
  final String label;

  static LiveStatus from(String? v) => LiveStatus.values.firstWhere((s) => s.value == v, orElse: () => LiveStatus.scheduled);
}

class LiveStream extends Equatable {
  const LiveStream({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.isPrivate,
    required this.privateMode,
    required this.price,
    required this.chatEnabled,
    required this.status,
    required this.viewers,
    required this.inviteCode,
    required this.peakViewers,
    required this.totalJoins,
    required this.ticketsSold,
    required this.revenue,
    required this.storeId,
    this.scheduledAt,
    this.startedAt,
    this.endedAt,
    this.storeName,
    this.storeSlug,
    this.storeLogoUrl,
    this.hostName = '',
    this.hostAvatarUrl = '',
    this.audience = LiveAudience.everyone,
    this.isHost = false,
    this.hasTicket = false,
  });

  factory LiveStream.fromJson(Map<String, dynamic> json) {
    final stats = J.map(json, 'stats') ?? const <String, dynamic>{};
    final store = J.map(json, 'store');
    final hostInfo = J.map(json, 'hostInfo') ?? const <String, dynamic>{};
    final me = J.map(json, 'me') ?? const <String, dynamic>{};
    return LiveStream(
      id: J.id(json),
      title: J.str(json, 'title'),
      description: J.str(json, 'description'),
      coverUrl: J.str(json, 'coverUrl'),
      isPrivate: J.str(json, 'visibility') == 'private',
      privateMode: J.strOrNull(json, 'privateMode'),
      price: J.integer(json, 'price'),
      chatEnabled: J.boolean(json, 'chatEnabled', true),
      status: LiveStatus.from(J.strOrNull(json, 'status')),
      viewers: J.integer(json, 'viewers', J.integer(stats, 'currentViewers')),
      inviteCode: J.str(json, 'inviteCode'),
      peakViewers: J.integer(stats, 'peakViewers'),
      totalJoins: J.integer(stats, 'totalJoins'),
      ticketsSold: J.integer(stats, 'ticketsSold'),
      revenue: J.integer(stats, 'revenue'),
      storeId: J.refId(json, 'store') ?? '',
      scheduledAt: J.date(json, 'scheduledAt'),
      startedAt: J.date(json, 'startedAt'),
      endedAt: J.date(json, 'endedAt'),
      storeName: store == null ? null : J.strOrNull(store, 'name'),
      storeSlug: store == null ? null : J.strOrNull(store, 'slug'),
      storeLogoUrl: store == null ? null : J.strOrNull(store, 'logoUrl'),
      hostName: J.str(hostInfo, 'name'),
      hostAvatarUrl: J.str(hostInfo, 'avatarUrl'),
      audience: LiveAudience.fromJson(J.map(json, 'audience'), visibility: J.str(json, 'visibility'), privateMode: J.strOrNull(json, 'privateMode')),
      isHost: J.boolean(me, 'isHost'),
      hasTicket: J.boolean(me, 'hasTicket'),
    );
  }

  final String id;
  final String title;
  final String description;
  final String coverUrl;
  final bool isPrivate;
  final String? privateMode; // invite | community | selected
  final int price;
  final bool chatEnabled;
  final LiveStatus status;
  final int viewers;
  final String inviteCode;
  final int peakViewers;
  final int totalJoins;
  final int ticketsSold;
  final int revenue;
  final String storeId;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? storeName;
  final String? storeSlug;
  final String? storeLogoUrl;

  /// Only on discovery lists (home, community).
  final String hostName;
  final String hostAvatarUrl;
  final LiveAudience audience;
  final bool isHost;
  final bool hasTicket;

  bool get isFree => price == 0;

  /// Can watch without buying anything (free, already bought, or own live).
  bool get canWatchFree => isFree || hasTicket || isHost;
  bool get isLive => status == LiveStatus.live;

  @override
  List<Object?> get props => [id, title, status, viewers, price, inviteCode, ticketsSold, coverUrl];
}

/// Who a live is for — shown as a chip on live cards.
enum LiveAudienceType { everyone, community, invite, selected }

class LiveAudience extends Equatable {
  const LiveAudience({required this.type, this.communityId, this.communityName = '', this.communitySlug = '', this.communityIconUrl = ''});

  static const everyone = LiveAudience(type: LiveAudienceType.everyone);

  factory LiveAudience.fromJson(Map<String, dynamic>? json, {String visibility = '', String? privateMode}) {
    final type = json == null ? (visibility == 'private' ? (privateMode ?? 'invite') : 'everyone') : J.str(json, 'type', 'everyone');
    return LiveAudience(
      type: LiveAudienceType.values.firstWhere((t) => t.name == type, orElse: () => LiveAudienceType.everyone),
      communityId: json == null ? null : J.strOrNull(json, 'communityId'),
      communityName: json == null ? '' : J.str(json, 'communityName'),
      communitySlug: json == null ? '' : J.str(json, 'communitySlug'),
      communityIconUrl: json == null ? '' : J.str(json, 'communityIconUrl'),
    );
  }

  final LiveAudienceType type;
  final String? communityId;
  final String communityName;
  final String communitySlug;
  final String communityIconUrl;

  /// Short label for the card chip.
  String get label => switch (type) {
    LiveAudienceType.everyone => 'Everyone',
    LiveAudienceType.community => communityName.isEmpty ? 'Community only' : '$communityName only',
    LiveAudienceType.invite => 'Invite only',
    LiveAudienceType.selected => 'Selected people',
  };

  @override
  List<Object?> get props => [type, communityId, communityName];
}

class LiveAccess extends Equatable {
  const LiveAccess({required this.allowed, required this.isHost, required this.needsTicket, this.reason});

  factory LiveAccess.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return LiveAccess(allowed: J.boolean(j, 'allowed'), isHost: J.boolean(j, 'isHost'), needsTicket: J.boolean(j, 'needsTicket'), reason: J.strOrNull(j, 'reason'));
  }

  final bool allowed;
  final bool isHost;
  final bool needsTicket;
  final String? reason; // login_required | private | ticket_required

  bool get isPrivateBlocked => reason == 'private';

  @override
  List<Object?> get props => [allowed, isHost, needsTicket, reason];
}

class LiveDetail extends Equatable {
  const LiveDetail({required this.live, required this.access, required this.storeName, required this.storeSlug, required this.storeLogoUrl});

  factory LiveDetail.fromJson(Map<String, dynamic> json) {
    final store = J.map(json, 'store') ?? const <String, dynamic>{};
    return LiveDetail(
      live: LiveStream.fromJson(J.map(json, 'live') ?? const {}),
      access: LiveAccess.fromJson(J.map(json, 'access')),
      storeName: J.str(store, 'name'),
      storeSlug: J.str(store, 'slug'),
      storeLogoUrl: J.str(store, 'logoUrl'),
    );
  }

  final LiveStream live;
  final LiveAccess access;
  final String storeName;
  final String storeSlug;
  final String storeLogoUrl;

  @override
  List<Object?> get props => [live, access];
}

/// Where and how to join a LiveKit room.
class LiveConnection {
  const LiveConnection({required this.url, required this.token});

  factory LiveConnection.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return LiveConnection(url: J.str(j, 'url'), token: J.str(j, 'token'));
  }

  final String url;
  final String token;
}

/// Calls section of a public store page.
class CallInfo extends Equatable {
  const CallInfo({
    required this.enabled,
    required this.online,
    required this.busy,
    required this.audioEnabled,
    required this.audioRate,
    required this.videoEnabled,
    required this.videoRate,
    required this.minMinutes,
    required this.maxMinutes,
  });

  factory CallInfo.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    final audio = J.map(j, 'audio') ?? const <String, dynamic>{};
    final video = J.map(j, 'video') ?? const <String, dynamic>{};
    return CallInfo(
      enabled: J.boolean(j, 'enabled'),
      online: J.boolean(j, 'online'),
      busy: J.boolean(j, 'busy'),
      audioEnabled: J.boolean(audio, 'enabled'),
      audioRate: J.integer(audio, 'ratePerMinute'),
      videoEnabled: J.boolean(video, 'enabled'),
      videoRate: J.integer(video, 'ratePerMinute'),
      minMinutes: J.integer(j, 'minMinutes', 1),
      maxMinutes: J.integer(j, 'maxMinutes', 120),
    );
  }

  final bool enabled;
  final bool online;
  final bool busy;
  final bool audioEnabled;
  final int audioRate;
  final bool videoEnabled;
  final int videoRate;
  final int minMinutes;
  final int maxMinutes;

  @override
  List<Object?> get props => [enabled, online, busy, audioRate, videoRate];
}

/// The creator's own call settings.
class CallSettings extends Equatable {
  const CallSettings({required this.enabled, required this.audioEnabled, required this.videoEnabled, required this.audioRate, required this.videoRate, required this.online});

  factory CallSettings.fromJson(Map<String, dynamic> json) => CallSettings(
    enabled: J.boolean(json, 'enabled'),
    audioEnabled: J.boolean(json, 'audioEnabled', true),
    videoEnabled: J.boolean(json, 'videoEnabled', true),
    audioRate: J.integer(json, 'audioRate'),
    videoRate: J.integer(json, 'videoRate'),
    online: J.boolean(json, 'online'),
  );

  final bool enabled;
  final bool audioEnabled;
  final bool videoEnabled;
  final int audioRate;
  final int videoRate;
  final bool online;

  @override
  List<Object?> get props => [enabled, audioEnabled, videoEnabled, audioRate, videoRate, online];
}

enum CallStatus {
  awaitingPayment('awaiting_payment'),
  requested('requested'),
  active('active'),
  completed('completed'),
  declined('declined'),
  missed('missed'),
  cancelled('cancelled');

  const CallStatus(this.value);
  final String value;

  static CallStatus from(String? v) => CallStatus.values.firstWhere((s) => s.value == v, orElse: () => CallStatus.cancelled);

  bool get isFinal => this == completed || this == declined || this == missed || this == cancelled;

  String get label => switch (this) {
    CallStatus.awaitingPayment => 'Waiting for payment',
    CallStatus.requested => 'Ringing',
    CallStatus.active => 'In progress',
    CallStatus.completed => 'Completed',
    CallStatus.declined => 'Declined',
    CallStatus.missed => 'Missed',
    CallStatus.cancelled => 'Cancelled',
  };
}

class CallSession extends Equatable {
  const CallSession({
    required this.id,
    required this.isHost,
    required this.isVideo,
    required this.ratePerMinute,
    required this.prepaidMinutes,
    required this.prepaidAmount,
    required this.note,
    required this.status,
    required this.billedMinutes,
    required this.billedAmount,
    required this.refundedAmount,
    required this.creatorEarning,
    required this.endReason,
    required this.otherName,
    required this.otherAvatarUrl,
    required this.storeName,
    this.requestedAt,
    this.connectedAt,
    this.endedAt,
    this.createdAt,
  });

  factory CallSession.fromJson(Map<String, dynamic> json) {
    final isHost = J.str(json, 'role') == 'host';
    final other = J.map(json, isHost ? 'caller' : 'host') ?? const <String, dynamic>{};
    final store = J.map(json, 'store') ?? const <String, dynamic>{};
    return CallSession(
      id: J.id(json),
      isHost: isHost,
      isVideo: J.str(json, 'type') == 'video',
      ratePerMinute: J.integer(json, 'ratePerMinute'),
      prepaidMinutes: J.integer(json, 'prepaidMinutes'),
      prepaidAmount: J.integer(json, 'prepaidAmount'),
      note: J.str(json, 'note'),
      status: CallStatus.from(J.strOrNull(json, 'status')),
      billedMinutes: J.integer(json, 'billedMinutes'),
      billedAmount: J.integer(json, 'billedAmount'),
      refundedAmount: J.integer(json, 'refundedAmount'),
      creatorEarning: J.integer(json, 'creatorEarning'),
      endReason: J.str(json, 'endReason'),
      otherName: J.str(other, 'name', isHost ? 'Caller' : 'Creator'),
      otherAvatarUrl: J.strOrNull(other, 'avatarUrl'),
      storeName: J.str(store, 'name'),
      requestedAt: J.date(json, 'requestedAt'),
      connectedAt: J.date(json, 'connectedAt'),
      endedAt: J.date(json, 'endedAt'),
      createdAt: J.date(json, 'createdAt'),
    );
  }

  final String id;
  final bool isHost;
  final bool isVideo;
  final int ratePerMinute;
  final int prepaidMinutes;
  final int prepaidAmount;
  final String note;
  final CallStatus status;
  final int billedMinutes;
  final int billedAmount;
  final int refundedAmount;
  final int creatorEarning;
  final String endReason;
  final String otherName;
  final String? otherAvatarUrl;
  final String storeName;
  final DateTime? requestedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;

  @override
  List<Object?> get props => [id, status, connectedAt, billedMinutes, refundedAmount];
}

class CallJoin {
  const CallJoin({required this.connection, required this.call, this.endsAt});

  final LiveConnection connection;
  final CallSession call;
  final DateTime? endsAt;
}