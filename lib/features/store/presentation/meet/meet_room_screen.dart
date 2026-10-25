// File: lib/features/store/presentation/meet/meet_room_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/meet_host_api.dart';
import '../../data/store_repository.dart';
import 'attendance_sheet.dart';

/// Arguments for the meeting room (GoRouter `extra`).
class MeetRoomArgs {
  const MeetRoomArgs({required this.meetId, required this.title, required this.connection, required this.isHost});

  final String meetId;
  final String title;
  final LiveConnection connection;
  final bool isHost;
}

/// In-app Virtual Meet: everyone can talk and turn on their camera.
/// The host can mute people, turn cameras off, ask people to unmute, remove
/// people, lock the meeting, share their screen and see who attended.
/// The screen stays on while the meeting is open.
class MeetRoomScreen extends StatefulWidget {
  const MeetRoomScreen({super.key, required this.args});

  final MeetRoomArgs args;

  @override
  State<MeetRoomScreen> createState() => _MeetRoomScreenState();
}

class _MeetRoomScreenState extends State<MeetRoomScreen> {
  final Room _room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
  EventsListener<RoomEvent>? _listener;
  bool _connecting = true;
  bool _ended = false;
  bool _removed = false;
  bool _leaving = false;
  String? _error;
  bool _front = true;
  bool _locked = false;
  bool _askShown = false;

  MeetRoomArgs get _args => widget.args;
  LocalParticipant? get _me => _room.localParticipant;
  bool get _micOn => _me?.isMicrophoneEnabled() ?? false;
  bool get _camOn => _me?.isCameraEnabled() ?? false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // keep the screen on during the meeting
    _connect();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
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
      _listener?.dispose();
      _listener = _room.createListener()
        ..on<ParticipantConnectedEvent>((_) => _refresh())
        ..on<ParticipantDisconnectedEvent>((_) => _refresh())
        ..on<TrackSubscribedEvent>((_) => _refresh())
        ..on<TrackUnsubscribedEvent>((_) => _refresh())
        ..on<TrackPublishedEvent>((_) => _refresh())
        ..on<TrackUnpublishedEvent>((_) => _refresh())
        ..on<TrackMutedEvent>(_onMuted)
        ..on<TrackUnmutedEvent>((_) => _refresh())
        ..on<LocalTrackPublishedEvent>((_) => _refresh())
        ..on<LocalTrackUnpublishedEvent>((_) => _refresh())
        ..on<ActiveSpeakersChangedEvent>((_) => _refresh())
        ..on<DataReceivedEvent>(_onData)
        ..on<RoomDisconnectedEvent>((e) {
          if (!mounted || _leaving) return;
          setState(() {
            _removed = e.reason == DisconnectReason.participantRemoved;
            _ended = true;
          });
        });
      await _room.connect(_args.connection.url, _args.connection.token);
      await _me?.setMicrophoneEnabled(true);
      await _me?.setCameraEnabled(true);
      if (_args.isHost) {
        MeetHostApi.isLocked(_args.meetId).then((v) {
          if (mounted) setState(() => _locked = v);
        }).catchError((_) {});
      }
      if (mounted) setState(() => _connecting = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Could not connect to the meeting. Check your internet and try again.';
        });
      }
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Our own mic/camera was turned off by the host → tell the person.
  void _onMuted(TrackMutedEvent e) {
    if (!_args.isHost && e.participant is LocalParticipant && mounted) {
      final video = e.publication.kind == TrackType.VIDEO;
      AppSnackbar.info(context, video ? 'The host turned your camera off' : 'The host muted you');
    }
    _refresh();
  }

  // ---------- data messages (host → guests) ----------

  bool _fromHost(RemoteParticipant? p) => p?.metadata?.contains('"host"') ?? false;

  void _onData(DataReceivedEvent event) {
    try {
      final msg = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      if (!_fromHost(event.participant)) return;
      if (msg['t'] == 'ask_unmute' && !_micOn) _showAsk(video: false);
      if (msg['t'] == 'ask_camera' && !_camOn) _showAsk(video: true);
    } catch (_) {
      // Not one of our messages.
    }
  }

  Future<void> _showAsk({required bool video}) async {
    if (_askShown || !mounted) return;
    _askShown = true;
    HapticFeedback.mediumImpact();
    final yes = await showAppSheet<bool>(
      context,
      builder: (ctx) => SheetBody(
        title: video ? 'The host asks you to turn on your camera' : 'The host asks you to unmute',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: Icon(video ? PhosphorIconsRegular.videoCamera : PhosphorIconsRegular.microphone),
              label: Text(video ? 'Turn on camera' : 'Unmute'),
            ),
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          ],
        ),
      ),
    );
    _askShown = false;
    if (yes == true) {
      if (video) {
        await _me?.setCameraEnabled(true);
      } else {
        await _me?.setMicrophoneEnabled(true);
      }
      _refresh();
    }
  }

  Future<void> _sendToGuests(Map<String, dynamic> msg, {String? identity}) async {
    try {
      await _me?.publishData(utf8.encode(jsonEncode(msg)), reliable: true, destinationIdentities: identity == null ? null : [identity]);
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Couldn’t send that — check your connection');
    }
  }

  // ---------- own controls ----------

  Future<void> _toggleMic() async {
    await _me?.setMicrophoneEnabled(!_micOn);
    HapticFeedback.selectionClick();
    _refresh();
  }

  Future<void> _toggleCam() async {
    await _me?.setCameraEnabled(!_camOn);
    HapticFeedback.selectionClick();
    _refresh();
  }

  Future<void> _flip() async {
    final track = _me?.videoTrackPublications.where((p) => p.source == TrackSource.camera).firstOrNull?.track;
    if (track is! LocalVideoTrack) return;
    _front = !_front;
    try {
      await track.restartTrack(CameraCaptureOptions(cameraPosition: _front ? CameraPosition.front : CameraPosition.back));
    } catch (_) {
      _front = !_front;
    }
  }

  // ---------- host controls ----------

  Future<void> _hostAction(Future<String> Function() run) async {
    try {
      final message = await run();
      HapticFeedback.selectionClick();
      if (mounted && message.isNotEmpty) AppSnackbar.success(context, message);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    }
    _refresh();
  }

  Future<void> _toggleLock() async {
    try {
      final v = await MeetHostApi.setLocked(_args.meetId, !_locked);
      if (!mounted) return;
      setState(() => _locked = v);
      AppSnackbar.success(context, v ? 'Meeting locked — no one new can join' : 'Meeting unlocked');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  Future<void> _openHostSheet() async {
    HapticFeedback.selectionClick();
    await showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final guests = _room.remoteParticipants.values.toList()..sort((a, b) => a.name.compareTo(b.name));
          Future<void> run(Future<void> Function() f) async {
            await f();
            if (ctx.mounted) setSheet(() {});
          }

          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.82),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Host controls', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _HostChip(icon: PhosphorIconsRegular.microphoneSlash, label: 'Mute all', onTap: () => run(() => _hostAction(() => MeetHostApi.mute(_args.meetId)))),
                        _HostChip(icon: PhosphorIconsRegular.videoCameraSlash, label: 'Cameras off', onTap: () => run(() => _hostAction(() => MeetHostApi.mute(_args.meetId, video: true)))),
                        _HostChip(
                          icon: PhosphorIconsRegular.handWaving,
                          label: 'Ask all to unmute',
                          onTap: () => run(() async {
                            await _sendToGuests({'t': 'ask_unmute'});
                            if (mounted) AppSnackbar.success(context, 'Asked everyone to unmute');
                          }),
                        ),
                        _HostChip(
                          icon: _locked ? PhosphorIconsRegular.lockOpen : PhosphorIconsRegular.lock,
                          label: _locked ? 'Unlock meeting' : 'Lock meeting',
                          highlighted: _locked,
                          onTap: () => run(_toggleLock),
                        ),
                        _HostChip(
                          icon: PhosphorIconsRegular.listChecks,
                          label: 'Who attended',
                          onTap: () => showAttendanceSheet(context, title: _args.title, load: () => MeetHostApi.meetAttendance(_args.meetId)),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('In the meeting · ${guests.length + 1}', style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    if (guests.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        child: Text('No one else has joined yet.', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: guests.length,
                          itemBuilder: (_, i) {
                            final p = guests[i];
                            final micOn = p.audioTrackPublications.any((pub) => !pub.muted);
                            final camOn = p.videoTrackPublications.any((pub) => !pub.muted && pub.source == TrackSource.camera);
                            final name = p.name.isEmpty ? 'Guest' : p.name;
                            return _GuestRow(
                              name: name,
                              micOn: micOn,
                              camOn: camOn,
                              onMute: () => run(() => _hostAction(() => MeetHostApi.mute(_args.meetId, identity: p.identity))),
                              onCamOff: () => run(() => _hostAction(() => MeetHostApi.mute(_args.meetId, identity: p.identity, video: true))),
                              onAskUnmute: () => run(() async {
                                await _sendToGuests({'t': 'ask_unmute'}, identity: p.identity);
                                if (mounted) AppSnackbar.success(context, 'Asked $name to unmute');
                              }),
                              onAskCamera: () => run(() async {
                                await _sendToGuests({'t': 'ask_camera'}, identity: p.identity);
                                if (mounted) AppSnackbar.success(context, 'Asked $name to turn on their camera');
                              }),
                              onRemove: () async {
                                final ok = await confirmAction(
                                  ctx,
                                  title: 'Remove $name?',
                                  message: 'They’ll leave the meeting. Lock the meeting if you don’t want them back.',
                                  confirmLabel: 'Remove',
                                  destructive: true,
                                );
                                if (ok) await run(() => _hostAction(() => MeetHostApi.remove(_args.meetId, p.identity)));
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    _refresh();
  }

  Future<void> _leave() async {
    if (_args.isHost && !_ended) {
      final choice = await showAppSheet<String>(
        context,
        builder: (ctx) => SheetBody(
          title: 'Leave the meeting?',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => Navigator.of(ctx).pop('end'),
                child: const Text('End meeting for everyone'),
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton(onPressed: () => Navigator.of(ctx).pop('leave'), child: const Text('Just leave (others stay)')),
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Stay')),
            ],
          ),
        ),
      );
      if (choice == null) return;
      if (choice == 'end') {
        try {
          await sl<StoreRepository>().endMeet(_args.meetId);
        } on ApiException catch (e) {
          if (mounted) AppSnackbar.error(context, e.displayMessage);
          return;
        }
      }
    }
    _leaving = true;
    if (mounted) Navigator.of(context).pop();
  }

  /// The first screen being shared in the room, if any.
  ({Participant who, VideoTrack track})? get _screenShare {
    final all = <Participant>[if (_me != null) _me!, ..._room.remoteParticipants.values];
    for (final p in all) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (pub.source == TrackSource.screenShareVideo && t is VideoTrack && !pub.muted) return (who: p, track: t);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Participant>[
      if (_me != null) _me!,
      ..._room.remoteParticipants.values,
    ];
    final share = _screenShare;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF0B0B12),
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_args.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                                Row(
                                  children: [
                                    Text('${tiles.length} in the meeting', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                    if (_locked) ...[
                                      const SizedBox(width: 8),
                                      const Icon(PhosphorIconsFill.lock, color: Color(0xFFFFB020), size: 12),
                                      const SizedBox(width: 3),
                                      const Text('Locked', style: TextStyle(color: Color(0xFFFFB020), fontSize: 12, fontWeight: FontWeight.w700)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (_args.isHost)
                            IconButton(tooltip: 'Host controls', onPressed: _openHostSheet, icon: const Icon(PhosphorIconsRegular.shieldStar, color: Colors.white)),
                          IconButton(tooltip: 'Leave', onPressed: _leave, icon: const Icon(AppIcons.close, color: Colors.white)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _connecting
                          ? const Center(child: CircularProgressIndicator())
                          : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                        child: share == null
                            ? _Grid(participants: tiles)
                            : Column(
                          children: [
                            Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _ScreenTile(track: share.track, who: share.who))),
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: tiles.length,
                                itemBuilder: (_, i) => SizedBox(width: 100, child: Padding(padding: const EdgeInsets.all(4), child: _Tile(participant: tiles[i]))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Control(icon: _micOn ? PhosphorIconsRegular.microphone : PhosphorIconsRegular.microphoneSlash, label: _micOn ? 'Mute' : 'Unmute', active: _micOn, onTap: _toggleMic),
                          _Control(icon: _camOn ? PhosphorIconsRegular.videoCamera : PhosphorIconsRegular.videoCameraSlash, label: _camOn ? 'Stop video' : 'Start video', active: _camOn, onTap: _toggleCam),
                          _Control(icon: AppIcons.refresh, label: 'Flip', active: true, onTap: _flip),
                          _Control(icon: AppIcons.phone, label: 'Leave', active: false, leave: true, onTap: _leave),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_error != null || _ended)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black87,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_removed ? PhosphorIconsRegular.userMinus : AppIcons.videoCamera, color: Colors.white54, size: 48),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                _error ?? (_removed ? 'The host removed you from this meeting.' : 'This meeting has ended.'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              if (_error != null) FilledButton(onPressed: _connect, child: const Text('Try again')),
                              TextButton(
                                onPressed: () {
                                  _leaving = true;
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Close', style: TextStyle(color: Colors.white70)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 250.ms),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1 person: full. 2: stacked. 3+: two columns (scrolls when many).
class _Grid extends StatelessWidget {
  const _Grid({required this.participants});

  final List<Participant> participants;

  @override
  Widget build(BuildContext context) {
    if (participants.length <= 2) {
      return Column(
        children: [
          for (final p in participants)
            Expanded(child: Padding(padding: const EdgeInsets.all(4), child: _Tile(participant: p))),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final rows = (participants.length / 2).ceil();
        final fitHeight = (box.maxHeight / rows).clamp(150.0, box.maxHeight);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: fitHeight.toDouble()),
          itemCount: participants.length,
          itemBuilder: (context, i) => Padding(padding: const EdgeInsets.all(4), child: _Tile(participant: participants[i])),
        );
      },
    );
  }
}

/// A shared screen, shown big above everyone else.
class _ScreenTile extends StatelessWidget {
  const _ScreenTile({required this.track, required this.who});

  final VideoTrack track;
  final Participant who;

  @override
  Widget build(BuildContext context) {
    final name = who is LocalParticipant ? 'You are' : '${who.name.isEmpty ? 'The host' : who.name} is';
    return Container(
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoTrackRenderer(track, fit: VideoViewFit.contain),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsRegular.screencast, color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text('$name sharing the screen', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    VideoTrack? video;
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t is VideoTrack && !pub.muted && pub.source == TrackSource.camera) video = t;
    }
    final micMuted = p.audioTrackPublications.isEmpty || p.audioTrackPublications.every((pub) => pub.muted);
    final name = p is LocalParticipant ? 'You' : (p.name.isEmpty ? 'Guest' : p.name);
    final isHost = p.metadata?.contains('"host"') ?? false;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.isSpeaking ? AppColors.success : Colors.transparent, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null)
            VideoTrackRenderer(video, fit: VideoViewFit.cover)
          else
            Center(
              child: CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
              ),
            ),
          Positioned(
            left: 6,
            bottom: 6,
            right: 6,
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (micMuted) ...[
                          const Icon(PhosphorIconsRegular.microphoneSlash, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(isHost ? '$name · Host' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({required this.icon, required this.label, required this.active, required this.onTap, this.leave = false, this.highlight = false});

  final IconData icon;
  final String label;
  final bool active;
  final bool leave;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg = leave
        ? AppColors.error
        : highlight
        ? AppColors.primary
        : (active ? Colors.white24 : AppColors.error.withValues(alpha: 0.85));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(15), child: Icon(icon, color: Colors.white, size: 22)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}

class _HostChip extends StatelessWidget {
  const _HostChip({required this.icon, required this.label, required this.onTap, this.highlighted = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? const Color(0xFFE8890A) : AppColors.primary;
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One person in the host sheet: mic, camera and remove.
/// Tapping a red (off) icon asks them to turn it on; a green (on) icon turns it off.
class _GuestRow extends StatelessWidget {
  const _GuestRow({
    required this.name,
    required this.micOn,
    required this.camOn,
    required this.onMute,
    required this.onCamOff,
    required this.onAskUnmute,
    required this.onAskCamera,
    required this.onRemove,
  });

  final String name;
  final bool micOn;
  final bool camOn;
  final VoidCallback onMute;
  final VoidCallback onCamOff;
  final VoidCallback onAskUnmute;
  final VoidCallback onAskCamera;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(name[0].toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('${micOn ? 'Mic on' : 'Muted'} · ${camOn ? 'Camera on' : 'Camera off'}', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: micOn ? 'Mute' : 'Ask to unmute',
            onPressed: micOn ? onMute : onAskUnmute,
            icon: Icon(micOn ? PhosphorIconsRegular.microphone : PhosphorIconsRegular.microphoneSlash, color: micOn ? AppColors.success : AppColors.error),
          ),
          IconButton(
            tooltip: camOn ? 'Turn camera off' : 'Ask to turn camera on',
            onPressed: camOn ? onCamOff : onAskCamera,
            icon: Icon(camOn ? PhosphorIconsRegular.videoCamera : PhosphorIconsRegular.videoCameraSlash, color: camOn ? AppColors.success : AppColors.error),
          ),
          IconButton(tooltip: 'Remove', onPressed: onRemove, icon: const Icon(PhosphorIconsRegular.userMinus, color: AppColors.error)),
        ],
      ),
    );
  }
}