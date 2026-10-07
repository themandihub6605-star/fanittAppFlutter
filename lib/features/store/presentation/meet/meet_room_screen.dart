import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/store_repository.dart';

/// Arguments for the meeting room (GoRouter `extra`).
class MeetRoomArgs {
  const MeetRoomArgs({required this.meetId, required this.title, required this.connection, required this.isHost});

  final String meetId;
  final String title;
  final LiveConnection connection;
  final bool isHost;
}

/// In-app Virtual Meet: everyone can talk and turn on their camera.
/// No Zoom, no passcode.
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
  bool _leaving = false;
  String? _error;
  bool _micOn = true;
  bool _camOn = true;
  bool _front = true;

  MeetRoomArgs get _args => widget.args;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
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
        ..on<TrackMutedEvent>((_) => _refresh())
        ..on<TrackUnmutedEvent>((_) => _refresh())
        ..on<LocalTrackPublishedEvent>((_) => _refresh())
        ..on<ActiveSpeakersChangedEvent>((_) => _refresh())
        ..on<RoomDisconnectedEvent>((_) {
          if (mounted && !_leaving) setState(() => _ended = true);
        });
      await _room.connect(_args.connection.url, _args.connection.token);
      await _room.localParticipant?.setMicrophoneEnabled(true);
      await _room.localParticipant?.setCameraEnabled(true);
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

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    await _room.localParticipant?.setMicrophoneEnabled(_micOn);
    HapticFeedback.selectionClick();
    _refresh();
  }

  Future<void> _toggleCam() async {
    _camOn = !_camOn;
    await _room.localParticipant?.setCameraEnabled(_camOn);
    HapticFeedback.selectionClick();
    _refresh();
  }

  Future<void> _flip() async {
    final track = _room.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (track is! LocalVideoTrack) return;
    _front = !_front;
    try {
      await track.restartTrack(CameraCaptureOptions(cameraPosition: _front ? CameraPosition.front : CameraPosition.back));
    } catch (_) {
      _front = !_front;
    }
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

  @override
  Widget build(BuildContext context) {
    final tiles = <Participant>[
      if (_room.localParticipant != null) _room.localParticipant!,
      ..._room.remoteParticipants.values,
    ];
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
                                Text('${tiles.length} in the meeting', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(tooltip: 'Leave', onPressed: _leave, icon: const Icon(AppIcons.close, color: Colors.white)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _connecting
                          ? const Center(child: CircularProgressIndicator())
                          : Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs), child: _Grid(participants: tiles)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Control(icon: _micOn ? AppIcons.speakerOn : AppIcons.speakerOff, label: _micOn ? 'Mute' : 'Unmute', active: _micOn, onTap: _toggleMic),
                          _Control(icon: AppIcons.videoCamera, label: _camOn ? 'Stop video' : 'Start video', active: _camOn, onTap: _toggleCam),
                          _Control(icon: AppIcons.refresh, label: 'Flip', active: true, onTap: _flip),
                          _Control(icon: AppIcons.phone, label: 'Leave', active: false, onTap: _leave),
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(AppIcons.videoCamera, color: Colors.white54, size: 48),
                            const SizedBox(height: AppSpacing.md),
                            Text(_error ?? 'This meeting has ended.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
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

class _Tile extends StatelessWidget {
  const _Tile({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    VideoTrack? video;
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t is VideoTrack && !pub.muted) video = t;
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
                radius: 34,
                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
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
                          const Icon(AppIcons.speakerOff, color: Colors.white, size: 12),
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
  const _Control({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final leave = label == 'Leave';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: leave ? AppColors.error : (active ? Colors.white24 : AppColors.error.withValues(alpha: 0.85)),
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