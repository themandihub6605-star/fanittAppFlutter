import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/services/socket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/store_repository.dart';

/// One screen for the whole life of a call:
///  ringing (creator answers) → calling (buyer waits) → in call → summary.
/// Kept in sync by socket events and a light poll.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.callId});

  final String callId;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final StoreRepository _repo = sl<StoreRepository>();
  CallSession? _call;
  String? _error;
  bool _busy = false;

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _joining = false;
  bool _micOn = true;
  bool _camOn = true;
  bool _frontCamera = true;
  DateTime? _endsAt;

  StreamSubscription<SocketEvent>? _socketSub;
  Timer? _poll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _socketSub = sl<SocketService>().events.listen((e) {
      if (e.name.startsWith('store_call') && e.data['callId']?.toString() == widget.callId) _load();
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      final status = _call?.status;
      if (status == null || !status.isFinal) _load();
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _room != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _poll?.cancel();
    _tick?.cancel();
    _leaveRoom();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final call = await _repo.call(widget.callId);
      if (!mounted) return;
      final wasActive = _call?.status == CallStatus.active;
      setState(() {
        _call = call;
        _error = null;
      });
      if (call.status == CallStatus.active && _room == null && !_joining) _join();
      if (call.status.isFinal && (wasActive || _room != null)) {
        _leaveRoom();
        HapticFeedback.mediumImpact();
      }
    } on ApiException catch (e) {
      if (mounted && _call == null) setState(() => _error = e.displayMessage);
    }
  }

  // ---------- LiveKit ----------

  Future<void> _join() async {
    _joining = true;
    try {
      final joined = await _repo.joinCall(widget.callId);
      final room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      _listener = room.createListener()
        ..on<ParticipantConnectedEvent>((_) => _refresh())
        ..on<ParticipantDisconnectedEvent>((_) => _refresh())
        ..on<TrackSubscribedEvent>((_) => _refresh())
        ..on<TrackUnsubscribedEvent>((_) => _refresh())
        ..on<LocalTrackPublishedEvent>((_) => _refresh());
      await room.connect(joined.connection.url, joined.connection.token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      if (joined.call.isVideo) await room.localParticipant?.setCameraEnabled(true);
      if (!mounted) {
        await room.disconnect();
        return;
      }
      setState(() {
        _room = room;
        _endsAt = joined.endsAt;
      });
      // The other side may join a moment later — billing (and the timer) start then.
      if (_endsAt == null) {
        Future<void>.delayed(const Duration(seconds: 3), () async {
          if (!mounted || _room == null) return;
          try {
            final again = await _repo.joinCall(widget.callId);
            if (mounted) setState(() => _endsAt = again.endsAt);
          } on ApiException {
            // Next poll picks it up.
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Could not connect the call. Check your internet.');
    } finally {
      _joining = false;
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _leaveRoom() {
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    if (room != null) {
      room.disconnect();
      room.dispose();
    }
  }

  // ---------- actions ----------

  Future<void> _act(Future<CallSession> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    await _room?.localParticipant?.setMicrophoneEnabled(_micOn);
    _refresh();
  }

  Future<void> _toggleCamera() async {
    _camOn = !_camOn;
    await _room?.localParticipant?.setCameraEnabled(_camOn);
    _refresh();
  }

  Future<void> _flip() async {
    final track = _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (track is! LocalVideoTrack) return;
    _frontCamera = !_frontCamera;
    try {
      await track.restartTrack(CameraCaptureOptions(cameraPosition: _frontCamera ? CameraPosition.front : CameraPosition.back));
    } catch (_) {
      _frontCamera = !_frontCamera;
    }
  }

  VideoTrack? get _remoteVideo {
    for (final p in _room?.remoteParticipants.values ?? const <RemoteParticipant>[]) {
      for (final pub in p.videoTrackPublications) {
        final track = pub.track;
        if (track != null && !pub.muted) return track;
      }
    }
    return null;
  }

  VideoTrack? get _localVideo {
    final track = _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
    return track is VideoTrack ? track : null;
  }

  bool get _otherJoined => (_room?.remoteParticipants.length ?? 0) > 0;

  String get _timerText {
    final endsAt = _endsAt;
    if (endsAt == null) return _otherJoined ? 'Connecting…' : 'Waiting for the other person…';
    final left = endsAt.difference(DateTime.now());
    if (left.isNegative) return 'Time’s up';
    final m = left.inMinutes;
    final s = left.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} left';
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B12),
        body: call == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, style: const TextStyle(color: Colors.white70)),
                          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Close')),
                        ],
                      ),
              )
            : switch (call.status) {
                CallStatus.active => _activeView(call),
                CallStatus.requested || CallStatus.awaitingPayment => _ringingView(call),
                _ => _summaryView(call),
              },
      ),
    );
  }

  Widget _header(CallSession call, String subtitle) {
    return Column(
      children: [
        UserAvatar(initials: call.otherName.isEmpty ? '?' : call.otherName[0].toUpperCase(), imageUrl: call.otherAvatarUrl, size: 104),
        const SizedBox(height: AppSpacing.md),
        Text(call.otherName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _ringingView(CallSession call) {
    final kind = call.isVideo ? 'video' : 'audio';
    final price = call.prepaidAmount > 0 ? ' · ${Fmt.money(call.prepaidAmount)}' : ' · free';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Spacer(),
            // Pulsing rings around the avatar
            Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < 2; i++)
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 2)),
                  )
                      .animate(onPlay: (c) => c.repeat(), delay: (700 * i).ms)
                      .scaleXY(begin: 0.7, end: 1.5, duration: 1400.ms)
                      .fadeOut(duration: 1400.ms),
                _header(
                  call,
                  call.isHost
                      ? 'Incoming $kind call · ${call.prepaidMinutes} min$price'
                      : (call.status == CallStatus.awaitingPayment ? 'Finishing payment…' : 'Calling… they have 2 minutes to answer'),
                ),
              ],
            ),
            if (call.isHost && call.note.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
                child: Text('“${call.note}”', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic)),
              ),
            ],
            const Spacer(),
            if (call.isHost)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(icon: AppIcons.close, color: AppColors.error, label: 'Decline', onTap: _busy ? null : () => _act(() => _repo.declineCall(call.id))),
                  _CallButton(
                    icon: call.isVideo ? AppIcons.videoCamera : AppIcons.phone,
                    color: AppColors.success,
                    label: 'Accept',
                    onTap: _busy ? null : () => _act(() => _repo.acceptCall(call.id)),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.08, duration: 700.ms),
                ],
              )
            else
              _CallButton(icon: AppIcons.close, color: AppColors.error, label: 'Cancel', onTap: _busy ? null : () => _act(() => _repo.cancelCall(call.id))),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _activeView(CallSession call) {
    final remote = _remoteVideo;
    final local = _localVideo;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (call.isVideo && remote != null)
          VideoTrackRenderer(remote, fit: VideoViewFit.cover)
        else
          Center(child: _header(call, _room == null ? 'Connecting…' : (_otherJoined ? 'On call' : 'Waiting for them to join…'))),
        if (call.isVideo && local != null && _camOn)
          Positioned(
            right: 16,
            top: MediaQuery.paddingOf(context).top + 60,
            width: 110,
            height: 160,
            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: VideoTrackRenderer(local, fit: VideoViewFit.cover)),
          ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text(_timerText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(icon: _micOn ? AppIcons.speakerOn : AppIcons.speakerOff, color: _micOn ? Colors.white24 : AppColors.error, label: _micOn ? 'Mute' : 'Unmute', onTap: _toggleMic),
                    if (call.isVideo) ...[
                      _CallButton(icon: AppIcons.videoCamera, color: _camOn ? Colors.white24 : AppColors.error, label: _camOn ? 'Camera off' : 'Camera on', onTap: _toggleCamera),
                      _CallButton(icon: AppIcons.refresh, color: Colors.white24, label: 'Flip', onTap: _flip),
                    ],
                    _CallButton(icon: AppIcons.phone, color: AppColors.error, label: 'End', onTap: _busy ? null : () => _act(() => _repo.endCall(call.id))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryView(CallSession call) {
    final title = switch (call.status) {
      CallStatus.completed => 'Call ended',
      CallStatus.declined => 'Call declined',
      CallStatus.missed => 'No answer',
      _ => 'Call cancelled',
    };
    final lines = <String>[
      if (call.billedMinutes > 0) '${call.billedMinutes} min · ${Fmt.money(call.billedAmount)}',
      if (call.isHost && call.creatorEarning > 0) 'You earned ${Fmt.money(call.creatorEarning)}',
      if (!call.isHost && call.refundedAmount > 0) '${Fmt.money(call.refundedAmount)} back in your Fanitt wallet',
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Spacer(),
            _header(call, title),
            const SizedBox(height: AppSpacing.lg),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
            ),
          ].animate(interval: 60.ms).fadeIn(duration: 300.ms),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(18), child: Icon(icon, color: Colors.white, size: 26)),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
