// File: lib/features/store/presentation/live/live_tickets_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/store_repository.dart';

/// Host view: everyone who bought a ticket for a live, newest first.
class LiveTicketsScreen extends StatefulWidget {
  const LiveTicketsScreen({super.key, required this.liveId, required this.title});

  final String liveId;
  final String title;

  static Future<void> open(BuildContext context, {required String liveId, required String title}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LiveTicketsScreen(liveId: liveId, title: title)));

  @override
  State<LiveTicketsScreen> createState() => _LiveTicketsScreenState();
}

class _LiveTicketsScreenState extends State<LiveTicketsScreen> {
  LiveTickets? _data;
  String? _error;
  bool _onlyNew = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final d = await sl<StoreRepository>().liveTickets(widget.liveId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t load tickets. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Tickets', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      ),
      body: _error != null && d == null
          ? ErrorView(message: _error!, onRetry: _fetch)
          : d == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator.adaptive(color: AppColors.primary, onRefresh: _fetch, child: _body(context, d)),
    );
  }

  Widget _body(BuildContext context, LiveTickets d) {
    final palette = context.palette;
    final live = d.live;
    final paid = d.paid;
    final newCount = paid.where((t) => t.isNew).length;
    final shown = _onlyNew ? paid.where((t) => t.isNew).toList() : d.tickets;
    final when = (live.isLive ? live.startedAt : live.scheduledAt)?.toLocal();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF3B5C), AppColors.primary, Color(0xFFFF8A4C)]),
            boxShadow: [BoxShadow(color: AppColors.error.withValues(alpha: 0.26), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(live.title.isEmpty ? widget.title : live.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
              const SizedBox(height: 4),
              Text(
                live.isLive ? '● Live now' : (when == null ? 'Start whenever you’re ready' : Fmt.weekdayDateTime(when)),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${paid.length}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1)),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 4),
                    child: Text(paid.length == 1 ? 'ticket sold' : 'tickets sold', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  if (newCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(99)),
                      child: Text('+$newCount today', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _GlassStat(label: 'Ticket price', value: live.isFree ? 'Free' : Fmt.money(live.price)),
                  const SizedBox(width: 8),
                  _GlassStat(label: 'You earn', value: Fmt.money(d.earned)),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('Ticket holders', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary))),
            if (newCount > 0)
              GestureDetector(
                onTap: () => setState(() => _onlyNew = !_onlyNew),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: _onlyNew ? AppColors.success : AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                  child: Text(_onlyNew ? 'New today ✓' : 'New today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _onlyNew ? Colors.white : AppColors.success)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.1)),
                  child: const Icon(AppIcons.receipt, size: 32, color: AppColors.primary),
                ),
                const SizedBox(height: 12),
                Text('No tickets yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                const SizedBox(height: 4),
                Text('Share your live — everyone who buys a ticket shows up here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 66, color: palette.border),
                  _TicketRow(ticket: shown[i]).animate(delay: (30 * i.clamp(0, 12)).ms).fadeIn(duration: 240.ms).slideX(begin: 0.04),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _GlassStat extends StatelessWidget {
  const _GlassStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket});

  final LiveTicket ticket;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final t = ticket;
    final color = t.refunded ? palette.textSecondary : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          UserAvatar(initials: _initials(t.name), imageUrl: t.avatarUrl.isEmpty ? null : t.avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.textPrimary))),
                    if (t.isNew && !t.refunded) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                        child: const Text('NEW', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.success, letterSpacing: 0.4)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  t.refunded ? 'Refunded' : (t.paidAt == null ? 'Bought a ticket' : 'Bought ${Fmt.relative(t.paidAt!.toLocal())}'),
                  style: TextStyle(fontSize: 12, color: t.refunded ? AppColors.error : palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
            child: Text(
              Fmt.money(t.amount),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color, decoration: t.refunded ? TextDecoration.lineThrough : null),
            ),
          ),
        ],
      ),
    );
  }
}