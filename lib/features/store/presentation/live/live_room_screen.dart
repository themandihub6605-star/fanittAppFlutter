import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/store_repository.dart';
import '../fanbox/fanbox_sheet.dart';

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
  const _ChatLine(this.name, this.text, {this.mine = false});
  final String name;
  final String text;
  final bool mine;
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
  final List<int> _hearts = [];
  final _random = Random();

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
    _connect();
  }

  @override
  void dispose() {
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
        ..on<ParticipantConnectedEvent>((_) => _refresh())
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

  // ---------- data messages ----------

  void _onData(DataReceivedEvent event) {
    try {
      final msg = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      if (msg['t'] == 'chat') {
        _addChat(_ChatLine((msg['n'] ?? 'Viewer').toString(), (msg['m'] ?? '').toString()));
      } else if (msg['t'] == 'heart') {
        _addHeart();
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

  void _addHeart() {
    if (!mounted) return;
    final id = _random.nextInt(1 << 30);
    setState(() => _hearts.add(id));
    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _hearts.remove(id));
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

  Future<void> _sendHeart() async {
    HapticFeedback.selectionClick();
    _addHeart();
    await _publish({'t': 'heart'}, reliable: false);
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
                    _TopBar(title: _args.title, viewers: _viewerCount, onClose: _close),
                    const Spacer(),
                    if (_args.chatEnabled) _ChatList(lines: _chat),
                    _BottomBar(
                      isHost: _args.isHost,
                      chatEnabled: _args.chatEnabled,
                      controller: _input,
                      micOn: _micOn,
                      camOn: _camOn,
                      onSend: _sendChat,
                      onHeart: _sendHeart,
                      onMic: _toggleMic,
                      onCamera: _toggleCamera,
                      onFlip: _flipCamera,
                      onFanBox: _args.isHost || _args.storeId.isEmpty
                          ? null
                          : () => showFanBoxSheet(context, storeId: _args.storeId, creatorName: _args.hostName.isEmpty ? 'the host' : _args.hostName, sentFrom: 'live'),
                    ),
                  ],
                ),
              ),
              // Floating hearts
              for (final id in _hearts)
                Positioned(
                  key: ValueKey(id),
                  right: 24 + (id % 40).toDouble(),
                  bottom: 90,
                  child: const Icon(AppIcons.heartFilled, color: Color(0xFFFF4D6D), size: 30)
                      .animate()
                      .moveY(begin: 0, end: -260, duration: 1700.ms, curve: Curves.easeOut)
                      .fadeOut(delay: 900.ms, duration: 800.ms)
                      .scaleXY(begin: 0.6, end: 1.2, duration: 400.ms),
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
  const _TopBar({required this.title, required this.viewers, required this.onClose});

  final String title;
  final int viewers;
  final VoidCallback onClose;

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
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(AppIcons.close, color: Colors.white)),
        ],
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({required this.lines});

  final List<_ChatLine> lines;

  @override
  Widget build(BuildContext context) {
    final recent = lines.length > 8 ? lines.sublist(lines.length - 8) : lines;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in recent)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(14)),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${line.name}  ', style: TextStyle(color: line.mine ? AppColors.sunrise : Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
                    TextSpan(text: line.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 200.ms).slideX(begin: -0.05),
        ],
      ),
    );
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
    required this.onMic,
    required this.onCamera,
    required this.onFlip,
    this.onFanBox,
  });

  final VoidCallback? onFanBox;

  final bool isHost;
  final bool chatEnabled;
  final TextEditingController controller;
  final bool micOn;
  final bool camOn;
  final VoidCallback onSend;
  final VoidCallback onHeart;
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
                ],
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
              GestureDetector(
                onTap: onHeart,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFF4D6D), Color(0xFFF4511E)])),
                  child: const Icon(AppIcons.heartFilled, color: Colors.white),
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
