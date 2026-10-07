import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/guards/profile_gate.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/payment_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/store_repository.dart';
import '../../../../core/services/share_service.dart';
import '../widgets/store_widgets.dart';
import 'meet_room_screen.dart';

/// Joins (or, for the host, starts) a meet and opens the in-app room.
Future<void> openMeetRoom(BuildContext context, String meetId) async {
  try {
    final joined = await sl<StoreRepository>().joinMeet(meetId);
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    await context.push(
      AppRoutes.meetRoom,
      extra: MeetRoomArgs(meetId: meetId, title: joined.meet.title, connection: joined.connection, isHost: joined.isHost),
    );
  } on ApiException catch (e) {
    if (context.mounted) AppSnackbar.error(context, e.displayMessage);
  }
}

/// A Virtual Meet: details, book, join (or start, for the host).
class MeetDetailScreen extends StatefulWidget {
  const MeetDetailScreen({super.key, required this.meetId});

  final String meetId;

  @override
  State<MeetDetailScreen> createState() => _MeetDetailScreenState();
}

class _MeetDetailScreenState extends State<MeetDetailScreen> {
  MeetDetail? _data;
  String? _error;
  bool _busy = false;
  Timer? _poll;

  StoreRepository get _repo => sl<StoreRepository>();

  @override
  void initState() {
    super.initState();
    _load();
    // Waiting for the host to start → check every 15 s so "Join" lights up by itself.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_data?.access.reason == 'not_started' || _data?.access.reason == 'too_early') _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.meet(widget.meetId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && _data == null) setState(() => _error = e.displayMessage);
    }
  }

  Future<void> _book(StoreMeet meet) async {
    if (!await ensureProfileComplete(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final booking = await _repo.bookMeet(meet.id);
      if (booking.requiresPayment) {
        final result = await sl<PaymentService>().checkout(orderId: booking.orderId, amount: booking.amount, description: meet.title);
        await _repo.verifyMeetBooking(
          bookingId: booking.bookingId,
          razorpayOrderId: result.orderId ?? booking.orderId!,
          paymentId: result.paymentId,
          signature: result.signature,
        );
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      AppSnackbar.success(context, 'You’re booked! Join here when it starts.');
      await _load();
    } on PaymentCancelled {
      // Closed the checkout.
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    await openMeetRoom(context, widget.meetId);
    if (!mounted) return;
    setState(() => _busy = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Virtual Meet'),
        actions: [
          if (d != null)
            ShareIconButton(
              size: 44,
              message: () => ShareService.session(
                id: d.meet.id,
                title: d.meet.title,
                host: d.meet.hostName,
                when: d.meet.scheduledAt,
                price: d.meet.price,
                mine: d.meet.isHost,
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: d == null
          ? (_error == null ? const LoadingView() : ErrorView(message: _error!, onRetry: _load))
          : AppRefresh(onRefresh: _load, child: _body(context, d)),
    );
  }

  Widget _body(BuildContext context, MeetDetail d) {
    final m = d.meet;
    final a = d.access;
    final palette = context.palette;
    final when = m.scheduledAt == null ? '' : Fmt.weekdayDateTime(m.scheduledAt!.toLocal());

    Widget action;
    switch (a.reason) {
      case 'cancelled':
        action = _Note(icon: AppIcons.close, color: AppColors.error, text: 'This meeting was cancelled.');
      case 'ended':
        action = _Note(icon: AppIcons.checkCircle, color: palette.textSecondary, text: 'This meeting has ended.');
      case 'too_early':
        action = _Note(icon: AppIcons.clock, color: AppColors.info, text: 'You can start this meeting 30 minutes before $when.');
      case 'not_booked':
        action = AppButton(
          label: m.isFree ? 'Book for free' : 'Book · ${Fmt.money(m.price)}',
          icon: AppIcons.calendar,
          isLoading: _busy,
          onPressed: _busy || m.spotsLeft == 0 ? null : () => _book(m),
        );
      case 'not_started':
        action = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Note(icon: AppIcons.checkCircle, color: AppColors.success, text: 'You’re booked. The Join button turns on as soon as the host starts — $when.'),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: 'Join meeting', icon: AppIcons.videoCamera, onPressed: null),
          ],
        );
      default:
        action = a.canJoin
            ? AppButton(
          label: a.isHost ? (m.isLive ? 'Rejoin meeting' : 'Start meeting') : 'Join meeting',
          icon: AppIcons.videoCamera,
          isLoading: _busy,
          onPressed: _busy ? null : _join,
        )
            : _Note(icon: AppIcons.lock, color: palette.textSecondary, text: 'Log in to book this meeting.');
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoreImage(url: m.coverUrl, icon: AppIcons.videoCamera),
                if (m.isLive)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(6)),
                      child: const Text('LIVE NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.6, duration: 900.ms),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(m.title, style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: m.hostSlug.isEmpty ? null : () => context.push(AppRoutes.creatorProfile(m.hostSlug)),
          child: Row(
            children: [
              UserAvatar(initials: m.hostName.isEmpty ? '?' : m.hostName[0].toUpperCase(), imageUrl: m.hostAvatarUrl.isEmpty ? null : m.hostAvatarUrl, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(a.isHost ? 'You’re hosting' : 'Hosted by ${m.hostName}', style: context.text.titleSmall)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _Chip(icon: AppIcons.calendar, text: when),
            _Chip(icon: AppIcons.clock, text: '${m.durationMinutes} min'),
            _Chip(icon: AppIcons.rupee, text: m.isFree ? 'Free' : Fmt.money(m.price)),
            if (m.spotsLeft != null) _Chip(icon: AppIcons.users, text: m.spotsLeft! <= 0 ? 'Full' : '${m.spotsLeft} spots left'),
          ],
        ),
        if (m.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(m.description, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.5)),
        ],
        const SizedBox(height: AppSpacing.xl),
        action,
        const SizedBox(height: AppSpacing.sm),
        Text('Meetings happen right here in the Fanitt app — no other app or passcode needed.', textAlign: TextAlign.center, style: context.text.bodySmall),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: palette.textSecondary),
          const SizedBox(width: 4),
          Text(text, style: context.text.labelMedium),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary))),
        ],
      ),
    );
  }
}