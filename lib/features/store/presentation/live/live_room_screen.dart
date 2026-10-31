// File: lib/features/store/presentation/live/live_room_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/meet_host_api.dart';
import '../../data/store_repository.dart';
import '../fanbox/fanbox_sheet.dart';
import '../meet/attendance_sheet.dart';

/// Arguments for the live room (passed as GoRouter `extra`).
class LiveRoomArgs {
  const LiveRoomArgs({required this.liveId, required this.title, required this.connection, required this.isHost, this.chatEnabled = true, this.storeId = '', this.hostName = ''});

  final String storeId;
  final String hostName;
  final String liveId;
  final String title;
  final LiveConnection connection;
  final bool isHost;
  final bool chatEnabled;
}

class _ChatLine {
  const _ChatLine(this.name, this.text, {this.mine = false, this.gift = false, this.identity = '', this.system = false, this.shout = false});
  final String name;
  final String text;
  final bool mine;

  /// A FanBox line ("sent ₹500 🎁") — highlighted in the chat.
  final bool gift;

  /// Who wrote it (LiveKit identity) — lets the host give them a shoutout.
  final String identity;

  /// "Rahul joined 👋" — small and quiet.
  final bool system;

  /// "📣 Shoutout to Rahul" — highlighted.
  final bool shout;
}

/// Reactions anyone can throw on the live. Others are ignored when received.
const _liveReactions = ['❤️', '🔥', '😂', '😍', '👏', '🎉', '💯', '😮'];

/// One-tap messages for viewers who don't want to type.
const _quickChats = ['👋 Hi!', '❤️ Love this', '🔥 Fire', '😂 Haha', '👏 Amazing', '🙏 Shoutout please'];

/// A FanBox someone sent during the live (comes from the server after payment).
class _FanBoxEvent {
  const _FanBoxEvent({required this.id, required this.name, required this.amount, required this.message});
  final String id;
  final String name;
  final int amount; // paise
  final String message;
}

/// A running live: the host broadcasts camera + mic, viewers watch.
/// Chat and reactions travel as LiveKit data messages.
class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen({super.key, required this.args});

  final LiveRoomArgs args;

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  final Room _room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
  EventsListener<RoomEvent>? _listener;
  final _input = TextEditingController();
  final List<_ChatLine> _chat = [];
  final _random = Random();

  // Floating reactions (id, emoji) + totals for the "on fire" moment.
  final List<(int, String)> _floaters = [];
  int _reactionTotal = 0;
  final List<DateTime> _recentReactions = [];
  bool _onFire = false;
  DateTime _fireCooldown = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _fireTimer;

  // My own reacting: tray, combo counter, send throttle.
  bool _trayOpen = false;
  int _combo = 0;
  Timer? _comboTimer;
  final List<DateTime> _sentTimes = [];

  // Shoutout banner (host → one viewer).
  String? _shoutName;
  bool _shoutForMe = false;
  Timer? _shoutTimer;

  // FanBox alerts: shown one at a time, total kept for the host.
  final List<_FanBoxEvent> _fanboxQueue = [];
  final Set<String> _seenFanBox = {};
  _FanBoxEvent? _fanboxShowing;
  Timer? _fanboxTimer;
  int _fanboxTotal = 0;
  int _fanboxCount = 0;

  bool _connecting = true;
  bool _ended = false;
  String? _error;
  bool _micOn = true;
  bool _camOn = true;
  bool _frontCamera = true;
  bool _leaving = false;

  LiveRoomArgs get _args => widget.args;

  String get _myName {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.name : 'Viewer';
  }

  @override
  void initState() {
    super.initState();
    // Keep the screen on for the whole live.
    WakelockPlus.enable().catchError((_) {});
    _connect();
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    _fanboxTimer?.cancel();
    _fireTimer?.cancel();
    _comboTimer?.cancel();
    _shoutTimer?.cancel();
    _input.dispose();
    _listener?.dispose();
    _room.disconnect();
    _room.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      _listener = _room.createListener()
        ..on<ParticipantConnectedEvent>(_onJoined)
        ..on<ParticipantDisconnectedEvent>((_) => _refresh())
        ..on<TrackSubscribedEvent>((_) => _refresh())
        ..on<TrackUnsubscribedEvent>((_) => _refresh())
        ..on<LocalTrackPublishedEvent>((_) => _refresh())
        ..on<DataReceivedEvent>(_onData)
        ..on<RoomDisconnectedEvent>((_) {
          if (mounted && !_leaving) setState(() => _ended = true);
        });

      await _room.connect(_args.connection.url, _args.connection.token);
      if (_args.isHost) {
        await _room.localParticipant?.setCameraEnabled(true);
        await _room.localParticipant?.setMicrophoneEnabled(true);
      }
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Could not connect to the live. Check your internet and try again.';
        });
      }
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// "Rahul joined 👋" — skipped in very big rooms so chat stays readable.
  void _onJoined(ParticipantConnectedEvent event) {
    _refresh();
    if (!_args.chatEnabled || _room.remoteParticipants.length > 150) return;
    final name = event.participant.name.trim();
    if (name.isEmpty) return;
    _addChat(_ChatLine(name, 'joined 👋', system: true));
  }

  bool _fromHost(Participant? p) => p != null && (p.videoTrackPublications.isNotEmpty || p.audioTrackPublications.isNotEmpty);
  // ---------- data messages ----------

  void _onData(DataReceivedEvent event) {
    try {
      final msg = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      if (msg['t'] == 'chat') {
        _addChat(_ChatLine((msg['n'] ?? 'Viewer').toString(), (msg['m'] ?? '').toString(), identity: event.participant?.identity ?? ''));
      } else if (msg['t'] == 'heart') {
        _onReaction('❤️'); // older app versions
      } else if (msg['t'] == 'react') {
        final emoji = (msg['e'] ?? '').toString();
        if (_liveReactions.contains(emoji)) _onReaction(emoji);
      } else if (msg['t'] == 'shout' && _fromHost(event.participant)) {
        // Only the host (the one sending video / audio) can give shoutouts.
        _onShout((msg['n'] ?? '').toString(), (msg['i'] ?? '').toString());
      } else if (msg['t'] == 'fanbox' && event.participant == null) {
        // Only trusted when it comes from the Fanitt server (no participant),
        // which sends it after the payment went through.
        _onFanBox(msg);
      }
    } catch (_) {
      // Ignore anything that isn't one of our messages.
    }
  }

  void _addChat(_ChatLine line) {
    if (!mounted || line.text.trim().isEmpty) return;
    setState(() {
      _chat.add(line);
      if (_chat.length > 60) _chat.removeAt(0);
    });
  }

  void _onFanBox(Map<String, dynamic> msg) {
    if (!mounted) return;
    final id = (msg['id'] ?? '').toString();
    final amount = (msg['a'] as num?)?.toInt() ?? 0;
    if (amount <= 0 || (id.isNotEmpty && !_seenFanBox.add(id))) return;
    final event = _FanBoxEvent(
      id: id.isEmpty ? '${DateTime.now().microsecondsSinceEpoch}' : id,
      name: (msg['n'] ?? 'A fan').toString(),
      amount: amount,
      message: (msg['m'] ?? '').toString(),
    );
    setState(() {
      _fanboxTotal += amount;
      _fanboxCount += 1;
      _chat.add(_ChatLine(event.name, 'sent a FanBox of ${Fmt.money(amount)} 🎁', gift: true));
      if (_chat.length > 60) _chat.removeAt(0);
      _fanboxQueue.add(event);
    });
    if (_fanboxShowing == null) _showNextFanBox();
  }

  void _showNextFanBox() {
    if (!mounted || _fanboxQueue.isEmpty) return;
    final next = _fanboxQueue.removeAt(0);
    setState(() => _fanboxShowing = next);
    _args.isHost ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact();
    for (var i = 0; i < 6; i++) {
      Timer(Duration(milliseconds: 120 * i), () => _float(i.isEven ? '❤️' : '🎉'));
    }
    _fanboxTimer?.cancel();
    _fanboxTimer = Timer(const Duration(milliseconds: 3800), () {
      if (!mounted) return;
      setState(() => _fanboxShowing = null);
      Timer(const Duration(milliseconds: 350), _showNextFanBox);
    });
  }

  /// One emoji floats up the right side.
  void _float(String emoji) {
    if (!mounted || _floaters.length >= 40) return;
    final id = _random.nextInt(1 << 30);
    setState(() => _floaters.add((id, emoji)));
    Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _floaters.removeWhere((f) => f.$1 == id));
    });
  }

  /// Any reaction (mine or someone else's): float it, count it, and when a
  /// lot arrive at once, show the "on fire" moment.
  void _onReaction(String emoji) {
    _float(emoji);
    if (!mounted) return;
    final now = DateTime.now();
    setState(() => _reactionTotal += 1);
    _recentReactions
      ..add(now)
      ..removeWhere((t) => now.difference(t) > const Duration(seconds: 5));
    if (!_onFire && _recentReactions.length >= 25 && now.isAfter(_fireCooldown)) {
      _fireCooldown = now.add(const Duration(seconds: 25));
      setState(() => _onFire = true);
      if (_args.isHost) HapticFeedback.heavyImpact();
      _fireTimer?.cancel();
      _fireTimer = Timer(const Duration(milliseconds: 2800), () {
        if (mounted) setState(() => _onFire = false);
      });
    }
  }

  void _onShout(String name, String identity) {
    if (!mounted || name.trim().isEmpty) return;
    final forMe = identity.isNotEmpty && identity == _room.localParticipant?.identity;
    setState(() {
      _shoutName = name;
      _shoutForMe = forMe;
      _chat.add(_ChatLine(name, forMe ? 'got a shoutout from the host — that’s you! 🎉' : 'got a shoutout from the host 📣', shout: true));
      if (_chat.length > 60) _chat.removeAt(0);
    });
    forMe ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact();
    for (var i = 0; i < 8; i++) {
      Timer(Duration(milliseconds: 90 * i), () => _float(i.isEven ? '🎉' : '👏'));
    }
    _shoutTimer?.cancel();
    _shoutTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _shoutName = null);
    });
  }

  Future<void> _publish(Map<String, dynamic> msg, {bool reliable = true}) async {
    try {
      await _room.localParticipant?.publishData(utf8.encode(jsonEncode(msg)), reliable: reliable);
    } catch (_) {
      // A dropped reaction isn't worth bothering the user about.
    }
  }

  Future<void> _sendChat() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final name = _myName;
    _addChat(_ChatLine(name, text, mine: true));
    await _publish({'t': 'chat', 'n': name, 'm': text.length > 200 ? text.substring(0, 200) : text});
  }

  Future<void> _sendHeart() => _sendReaction('❤️');

  /// Throw a reaction. Shows instantly; at most ~6 per second go out to
  /// everyone (fast tappers still see all of theirs).
  Future<void> _sendReaction(String emoji) async {
    HapticFeedback.selectionClick();
    _onReaction(emoji);
    setState(() => _combo += 1);
    _comboTimer?.cancel();
    _comboTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _combo = 0);
    });
    final now = DateTime.now();
    _sentTimes.removeWhere((t) => now.difference(t) > const Duration(seconds: 1));
    if (_sentTimes.length >= 6) return;
    _sentTimes.add(now);
    // Old app versions only understand hearts.
    await _publish(emoji == '❤️' ? {'t': 'heart'} : {'t': 'react', 'e': emoji}, reliable: false);
  }

  void _toggleTray() {
    HapticFeedback.selectionClick();
    setState(() => _trayOpen = !_trayOpen);
  }

  Future<void> _sendQuick(String text) async {
    HapticFeedback.selectionClick();
    final name = _myName;
    _addChat(_ChatLine(name, text, mine: true));
    await _publish({'t': 'chat', 'n': name, 'm': text});
  }

  /// Host taps a chat line → shoutout to that viewer, seen by everyone.
  Future<void> _offerShoutout(_ChatLine line) async {
    if (!_args.isHost || line.identity.isEmpty || line.mine || line.gift || line.system || line.shout) return;
    final ok = await confirmAction(
      context,
      title: 'Shoutout to ${line.name}?',
      message: 'Everyone watching will see it — and ${line.name} gets a special alert.',
      confirmLabel: 'Give shoutout',
    );
    if (!ok || !mounted) return;
    _onShout(line.name, line.identity);
    await _publish({'t': 'shout', 'n': line.name, 'i': line.identity});
  }

  // ---------- host controls ----------

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    await _room.localParticipant?.setMicrophoneEnabled(_micOn);
    _refresh();
  }

  Future<void> _toggleCamera() async {
    _camOn = !_camOn;
    await _room.localParticipant?.setCameraEnabled(_camOn);
    _refresh();
  }

  Future<void> _flipCamera() async {
    final track = _room.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (track is! LocalVideoTrack) return;
    _frontCamera = !_frontCamera;
    try {
      await track.restartTrack(CameraCaptureOptions(cameraPosition: _frontCamera ? CameraPosition.front : CameraPosition.back));
    } catch (_) {
      _frontCamera = !_frontCamera;
      if (mounted) AppSnackbar.error(context, 'Could not switch camera');
    }
  }

  Future<void> _close() async {
    if (_args.isHost && !_ended) {
      final ok = await confirmAction(context, title: 'End your live?', message: 'Everyone watching will be disconnected.', confirmLabel: 'End live', destructive: true);
      if (!ok) return;
      try {
        await sl<StoreRepository>().endLive(_args.liveId);
      } on ApiException catch (e) {
        if (mounted) AppSnackbar.error(context, e.displayMessage);
        return;
      }
    }
    _leaving = true;
    if (mounted) Navigator.of(context).pop();
  }

  VideoTrack? get _videoTrack {
    if (_args.isHost) {
      final track = _room.localParticipant?.videoTrackPublications.firstOrNull?.track;
      return track is VideoTrack ? track : null;
    }
    for (final p in _room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final track = pub.track;
        if (track != null && !pub.muted) return track;
      }
    }
    return null;
  }

  int get _viewerCount => _room.remoteParticipants.length;

  @override
  Widget build(BuildContext context) {
    final track = _videoTrack;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Video
              if (track != null && (!_args.isHost || _camOn))
                VideoTrackRenderer(track, fit: VideoViewFit.cover)
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_args.isHost ? AppIcons.videoCamera : AppIcons.broadcast, color: Colors.white38, size: 48),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _connecting ? 'Connecting…' : (_args.isHost ? 'Camera is off' : 'Waiting for the host…'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              // Readability gradients
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Colors.transparent, Colors.transparent, Color(0xCC000000)],
                    stops: [0, 0.2, 0.55, 1],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      title: _args.title,
                      viewers: _viewerCount,
                      onClose: _close,
                      // Host sees what came in during this live.
                      fanboxTotal: _args.isHost ? _fanboxTotal : 0,
                      fanboxCount: _args.isHost ? _fanboxCount : 0,
                      reactions: _reactionTotal,
                    ),
                    const Spacer(),
                    if (_args.chatEnabled) _ChatList(lines: _chat, onTapLine: _args.isHost ? _offerShoutout : null),
                    _BottomBar(
                      isHost: _args.isHost,
                      chatEnabled: _args.chatEnabled,
                      controller: _input,
                      micOn: _micOn,
                      camOn: _camOn,
                      onSend: _sendChat,
                      onHeart: _sendHeart,
                      onReact: _sendReaction,
                      onToggleTray: _toggleTray,
                      trayOpen: _trayOpen,
                      combo: _combo,
                      onQuick: _args.isHost ? null : _sendQuick,
                      onMic: _toggleMic,
                      onCamera: _toggleCamera,
                      onFlip: _flipCamera,
                      onWatched: _args.isHost
                          ? () => showAttendanceSheet(context, title: _args.title, load: () => MeetHostApi.liveAttendance(_args.liveId))
                          : null,
                      onFanBox: _args.isHost || _args.storeId.isEmpty
                          ? null
                          : () => showFanBoxSheet(
                        context,
                        storeId: _args.storeId,
                        creatorName: _args.hostName.isEmpty ? 'the host' : _args.hostName,
                        sentFrom: 'live',
                        liveId: _args.liveId,
                      ),
                    ),
                  ],
                ),
              ),
              // Floating reactions
              for (final f in _floaters)
                Positioned(
                  key: ValueKey(f.$1),
                  right: 18 + (f.$1 % 56).toDouble(),
                  bottom: 100,
                  child: IgnorePointer(
                    child: Text(f.$2, style: TextStyle(fontSize: 26 + (f.$1 % 3) * 4.0))
                        .animate()
                        .moveY(begin: 0, end: -300 - (f.$1 % 80).toDouble(), duration: 1900.ms, curve: Curves.easeOut)
                        .moveX(begin: 0, end: ((f.$1 % 2 == 0) ? -1 : 1) * (12 + (f.$1 % 24)).toDouble(), duration: 1900.ms, curve: Curves.easeInOut)
                        .fadeOut(delay: 1000.ms, duration: 900.ms)
                        .scaleXY(begin: 0.5, end: 1.15, duration: 380.ms, curve: Curves.easeOutBack),
                  ),
                ),
              // "On fire" moment when lots of reactions land together
              if (_onFire)
                const Positioned(left: 0, right: 0, top: 96, child: IgnorePointer(child: _OnFireBanner())),
              // Shoutout banner
              if (_shoutName != null)
                Positioned.fill(
                  child: IgnorePointer(child: _ShoutoutBanner(key: ValueKey('$_shoutName$_shoutForMe'), name: _shoutName!, forMe: _shoutForMe)),
                ),
              // FanBox alert (one at a time).
              if (_fanboxShowing != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _FanBoxAlert(key: ValueKey(_fanboxShowing!.id), event: _fanboxShowing!, forHost: _args.isHost),
                  ),
                ),
              if (_error != null || _ended) _EndOverlay(message: _error ?? (_args.isHost ? 'Your live has ended.' : 'This live has ended.'), onRetry: _error != null ? _connect : null),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.viewers, required this.onClose, this.fanboxTotal = 0, this.fanboxCount = 0, this.reactions = 0});

  /// Reactions thrown in this live (everyone sees it).
  final int reactions;

  final String title;
  final int viewers;
  final VoidCallback onClose;

  /// Host only: FanBox money received in this live.
  final int fanboxTotal;
  final int fanboxCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(6)),
            child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.6)),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.65, duration: 900.ms),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                const Icon(AppIcons.eye, color: Colors.white, size: 13),
                const SizedBox(width: 4),
                Text('$viewers', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
          ),
          if (reactions > 0) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  const Text('❤️', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(Fmt.compact(reactions), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
            ),
          ],
          if (fanboxTotal > 0) ...[
            const SizedBox(width: AppSpacing.xs),
            Tooltip(
              message: '$fanboxCount FanBox${fanboxCount == 1 ? '' : 'es'} in this live',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                ),
                child: Row(
                  children: [
                    const Icon(AppIcons.gift, color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text(Fmt.money(fanboxTotal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ],
                ),
              ),
            ).animate(key: ValueKey(fanboxTotal)).scale(begin: const Offset(1.3, 1.3), duration: 400.ms, curve: Curves.easeOutBack),
          ],
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(AppIcons.close, color: Colors.white)),
        ],
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({required this.lines, this.onTapLine});

  final List<_ChatLine> lines;

  /// Host only: tap a viewer's message to give them a shoutout.
  final ValueChanged<_ChatLine>? onTapLine;

  @override
  Widget build(BuildContext context) {
    final recent = lines.length > 8 ? lines.sublist(lines.length - 8) : lines;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in recent)
            GestureDetector(
              onTap: onTapLine == null || line.identity.isEmpty || line.mine ? null : () => onTapLine!(line),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: line.system ? 4 : 6),
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
                decoration: line.gift
                    ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(colors: [const Color(0xFFF4511E).withValues(alpha: 0.85), const Color(0xFFEC2A78).withValues(alpha: 0.85)]),
                )
                    : line.shout
                    ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(colors: [const Color(0xFF7C3AED).withValues(alpha: 0.85), const Color(0xFF2563EB).withValues(alpha: 0.85)]),
                )
                    : BoxDecoration(color: Colors.black.withValues(alpha: line.system ? 0.22 : 0.35), borderRadius: BorderRadius.circular(14)),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${line.name}  ',
                        style: TextStyle(
                          color: line.gift || line.shout ? Colors.white : (line.mine ? AppColors.sunrise : Colors.white70),
                          fontWeight: FontWeight.w700,
                          fontSize: line.system ? 12 : 13,
                        ),
                      ),
                      TextSpan(
                        text: line.text,
                        style: TextStyle(
                          color: line.system ? Colors.white70 : Colors.white,
                          fontSize: line.system ? 12 : 13,
                          fontWeight: line.gift || line.shout ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 200.ms).slideX(begin: -0.05),
          if (onTapLine != null && recent.any((l) => l.identity.isNotEmpty && !l.mine))
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Tip: tap a message to give a shoutout 📣', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

/// Big animated FanBox alert: gift pops in, the amount counts up, sparks fly.
class _FanBoxAlert extends StatelessWidget {
  const _FanBoxAlert({super.key, required this.event, required this.forHost});

  final _FanBoxEvent event;
  final bool forHost;

  static const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);
  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 2))];

  @override
  Widget build(BuildContext context) {
    const sparks = 12;
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Soft glow
                Container(
                  width: 150,
                  height: 150,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x66FF8A50), Color(0x00FF8A50)])),
                ).animate().scale(begin: const Offset(0.3, 0.3), duration: 600.ms, curve: Curves.easeOut),
                // Sparks flying out
                for (var i = 0; i < sparks; i++)
                  Builder(builder: (_) {
                    final angle = i * 2 * pi / sparks;
                    final distance = 90.0 + (i % 3) * 14;
                    return Icon(
                      i.isEven ? AppIcons.sparkle : AppIcons.heartFilled,
                      size: i.isEven ? 16 : 13,
                      color: i % 3 == 0 ? const Color(0xFFFFD166) : (i.isEven ? Colors.white : const Color(0xFFFF8FB8)),
                    )
                        .animate(delay: 250.ms)
                        .move(begin: Offset.zero, end: Offset(cos(angle) * distance, sin(angle) * distance * 0.8), duration: 900.ms, curve: Curves.easeOutCubic)
                        .fadeOut(delay: 500.ms, duration: 500.ms);
                  }),
                // Gift
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _gradient,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Color(0x66EC2A78), blurRadius: 24, offset: Offset(0, 8))],
                  ),
                  child: const Icon(AppIcons.gift, color: Colors.white, size: 44),
                )
                    .animate()
                    .scale(begin: const Offset(0.2, 0.2), duration: 650.ms, curve: Curves.elasticOut)
                    .then(delay: 150.ms)
                    .shake(hz: 4, rotation: 0.08, duration: 450.ms),
              ],
            ),
          ),
          // Amount counts up
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: event.amount.toDouble()),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              Fmt.money(value.round()),
              style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1, shadows: _shadow),
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 300.ms).scale(begin: const Offset(0.7, 0.7), delay: 200.ms, duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 2),
          Text(
            forHost ? 'FanBox from ${event.name} 🎉' : '${event.name} sent a FanBox 🎁',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, shadows: _shadow),
          ).animate().fadeIn(delay: 350.ms, duration: 300.ms).slideY(begin: 0.3, delay: 350.ms, duration: 300.ms),
          if (event.message.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(16)),
              child: Text(
                '“${event.message}”',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
              ),
            ).animate().fadeIn(delay: 500.ms, duration: 300.ms),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .then(delay: 3000.ms)
        .fadeOut(duration: 400.ms)
        .slideY(end: -0.08, duration: 400.ms);
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isHost,
    required this.chatEnabled,
    required this.controller,
    required this.micOn,
    required this.camOn,
    required this.onSend,
    required this.onHeart,
    required this.onReact,
    required this.onToggleTray,
    required this.trayOpen,
    required this.combo,
    this.onQuick,
    required this.onMic,
    required this.onCamera,
    required this.onFlip,
    this.onWatched,
    this.onFanBox,
  });

  final VoidCallback? onFanBox;

  /// Host: who watched and for how long.
  final VoidCallback? onWatched;

  final bool isHost;
  final bool chatEnabled;
  final TextEditingController controller;
  final bool micOn;
  final bool camOn;
  final VoidCallback onSend;
  final VoidCallback onHeart;
  final ValueChanged<String> onReact;
  final VoidCallback onToggleTray;
  final bool trayOpen;

  /// My taps in a row ("x12" over the heart).
  final int combo;

  /// Viewers: one-tap messages (null for the host).
  final ValueChanged<String>? onQuick;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      child: Column(
        children: [
          if (isHost)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundButton(icon: micOn ? AppIcons.speakerOn : AppIcons.speakerOff, active: micOn, onTap: onMic, label: micOn ? 'Mute' : 'Unmute'),
                  const SizedBox(width: AppSpacing.md),
                  _RoundButton(icon: AppIcons.videoCamera, active: camOn, onTap: onCamera, label: camOn ? 'Camera off' : 'Camera on'),
                  const SizedBox(width: AppSpacing.md),
                  _RoundButton(icon: AppIcons.refresh, active: true, onTap: onFlip, label: 'Flip camera'),
                  if (onWatched != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    _RoundButton(icon: AppIcons.users, active: true, onTap: onWatched!, label: 'Who watched'),
                  ],
                ],
              ),
            ),
          // Reaction tray
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: !trayOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white24)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final e in _liveReactions)
                      _TrayEmoji(emoji: e, onTap: () => onReact(e)),
                  ],
                ),
              ).animate().fadeIn(duration: 180.ms).slideY(begin: 0.3, curve: Curves.easeOutCubic),
            ),
          ),
          // Quick messages (viewers)
          if (chatEnabled && onQuick != null && !trayOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _quickChats.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => onQuick!(_quickChats[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
                      child: Text(_quickChats[i], style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              if (chatEnabled)
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    maxLength: 200,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Say something…',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.12),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      suffixIcon: IconButton(onPressed: onSend, icon: const Icon(AppIcons.send, color: Colors.white)),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (onFanBox != null) ...[
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: onFanBox,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.18)),
                    child: const Icon(AppIcons.gift, color: Colors.white),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.sm),
              // Emoji tray
              GestureDetector(
                onTap: onToggleTray,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: trayOpen ? 0.32 : 0.18),
                    border: trayOpen ? Border.all(color: Colors.white, width: 1.5) : null,
                  ),
                  child: trayOpen ? const Icon(AppIcons.close, color: Colors.white, size: 20) : const Text('😍', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Heart — tap fast for a combo, hold for more emojis
              GestureDetector(
                onTap: onHeart,
                onLongPress: onToggleTray,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFF4D6D), Color(0xFFF4511E)])),
                      child: const Icon(AppIcons.heartFilled, color: Colors.white),
                    ).animate(key: ValueKey(combo)).scaleXY(begin: combo > 0 ? 0.85 : 1, end: 1, duration: 220.ms, curve: Curves.easeOutBack),
                    if (combo > 1)
                      Positioned(
                        top: -26,
                        left: -6,
                        right: -6,
                        child: Center(
                          child: Text(
                            'x$combo',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, shadows: [Shadow(color: Color(0xAA000000), blurRadius: 8)]),
                          ).animate(key: ValueKey('c$combo')).scaleXY(begin: 1.5, end: 1, duration: 200.ms, curve: Curves.easeOutBack),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.active, required this.onTap, required this.label});

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: active ? Colors.white.withValues(alpha: 0.18) : AppColors.error,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon, color: Colors.white, size: 22)),
        ),
      ),
    );
  }
}

class _EndOverlay extends StatelessWidget {
  const _EndOverlay({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.broadcast, color: Colors.white54, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: AppSpacing.lg),
              if (onRetry != null) FilledButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Close', style: TextStyle(color: Colors.white70))),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 250.ms),
    );
  }
}

class _TrayEmoji extends StatelessWidget {
  const _TrayEmoji({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send $emoji',
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Text(emoji, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }
}

/// "🔥 This live is on fire!" — when lots of reactions land together.
class _OnFireBanner extends StatelessWidget {
  const _OnFireBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Color(0xFFFF8A00), Color(0xFFFF2D55)]),
          boxShadow: const [BoxShadow(color: Color(0x66FF2D55), blurRadius: 20, offset: Offset(0, 6))],
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: const Text('🔥 This live is on fire!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
      )
          .animate()
          .scale(begin: const Offset(0.5, 0.5), duration: 450.ms, curve: Curves.elasticOut)
          .then()
          .shake(hz: 3, rotation: 0.03, duration: 500.ms)
          .then(delay: 1300.ms)
          .fadeOut(duration: 400.ms),
    );
  }
}

/// Big "📣 Shoutout to Rahul!" card. The viewer it's for gets "That's you!".
class _ShoutoutBanner extends StatelessWidget {
  const _ShoutoutBanner({super.key, required this.name, required this.forMe});

  final String name;
  final bool forMe;

  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 2))];

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.35),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C3AED), Color(0xFF2563EB)]),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x667C3AED), blurRadius: 24, offset: Offset(0, 8))],
            ),
            alignment: Alignment.center,
            child: const Text('📣', style: TextStyle(fontSize: 40)),
          ).animate().scale(begin: const Offset(0.2, 0.2), duration: 600.ms, curve: Curves.elasticOut).then(delay: 100.ms).shake(hz: 4, rotation: 0.06, duration: 400.ms),
          const SizedBox(height: 10),
          Text(
            forMe ? 'Shoutout to you! 🎉' : 'Shoutout to $name!',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, shadows: _shadow),
          ).animate().fadeIn(delay: 200.ms, duration: 300.ms).scale(begin: const Offset(0.8, 0.8), delay: 200.ms, duration: 350.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 2),
          Text(
            forMe ? 'The host gave you a shoutout' : 'from the host',
            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700, shadows: _shadow),
          ).animate().fadeIn(delay: 350.ms, duration: 300.ms),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).then(delay: 2800.ms).fadeOut(duration: 400.ms);
  }
}