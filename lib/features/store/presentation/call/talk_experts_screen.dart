// File: lib/features/store/presentation/call/talk_experts_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/store_repository.dart';
import 'request_call_sheet.dart';

/// "Talk 1:1 with experts" — See all. Search, category chips (from the
/// admin categories that have experts), "Online now", and every expert
/// taking audio / video calls. Online first.
class TalkExpertsScreen extends StatefulWidget {
  const TalkExpertsScreen({super.key});

  /// Route for this screen (registered in app_router.dart).
  static const route = '/app/experts';

  @override
  State<TalkExpertsScreen> createState() => _TalkExpertsScreenState();
}

class _TalkExpertsScreenState extends State<TalkExpertsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  List<ExpertCategory> _categories = const [];
  String? _category; // null = All
  bool _onlineOnly = false;

  final List<CallExpert> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore(force: true);
  }

  Future<void> _loadMore({bool force = false}) async {
    if ((_loading && !force) || !_hasMore) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final next = await sl<StoreRepository>().callExperts(page: _page + 1, category: _category, search: _search.text, online: _onlineOnly);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(next.items);
        _page = next.page;
        _hasMore = next.hasMore;
        // Keep the chips from the first unfiltered page (so they don't vanish when one is picked).
        if (next.page == 1 && _category == null && next.categories.isNotEmpty) _categories = next.categories;
      });
    } catch (_) {
      if (mounted && gen == _generation) setState(() => _error = 'Could not load experts. Pull to try again.');
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  void _pickCategory(String? id) {
    if (_category == id) return;
    HapticFeedback.selectionClick();
    setState(() => _category = id);
    _reload();
  }

  void _toggleOnline() {
    HapticFeedback.selectionClick();
    setState(() => _onlineOnly = !_onlineOnly);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Talk 1:1 with experts')),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _reload);
              },
              decoration: InputDecoration(
                hintText: 'Search experts by name',
                prefixIcon: Icon(AppIcons.search, size: 20, color: palette.textSecondary),
                filled: true,
                fillColor: palette.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: palette.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: palette.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
              ),
            ),
          ),
          // Chips: All · Online now · categories
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 6),
              children: [
                _Chip(label: 'All', selected: _category == null && !_onlineOnly, onTap: () {
                  if (_onlineOnly) setState(() => _onlineOnly = false);
                  if (_category != null) {
                    _pickCategory(null);
                  } else {
                    _reload();
                  }
                }),
                _Chip(label: 'Online now', dot: true, selected: _onlineOnly, onTap: _toggleOnline),
                for (final c in _categories) _Chip(label: '${c.label} · ${c.count}', selected: _category == c.id, onTap: () => _pickCategory(_category == c.id ? null : c.id)),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator.adaptive(
              color: AppColors.primary,
              onRefresh: _reload,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty && _loading) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 100),
          _error != null
              ? ErrorView(message: _error!, onRetry: _reload)
              : MessageView(
            icon: AppIcons.phone,
            title: 'No experts found',
            message: _onlineOnly ? 'Nobody in this list is online right now — try All.' : 'Try another category or search.',
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))),
          );
        }
        return _ExpertRow(expert: _items[i]).animate(delay: (30 * i.clamp(0, 8)).ms).fadeIn(duration: 220.ms);
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.dot = false});

  final String label;
  final bool selected;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : palette.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? AppColors.primary : palette.border.withValues(alpha: 0.8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot) ...[
                Container(width: 7, height: 7, decoration: BoxDecoration(color: selected ? Colors.white : const Color(0xFF22C55E), shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Colors.white : palette.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One expert: photo with status dot, name, category · status, rates and
/// "Call" (online) or "Visit" (offline / busy).
class _ExpertRow extends StatelessWidget {
  const _ExpertRow({required this.expert});

  final CallExpert expert;

  String _rate(int paise) => paise <= 0 ? 'Free' : '${Fmt.money(paise)}/min';

  void _openProfile(BuildContext context) {
    HapticFeedback.selectionClick();
    final c = expert.creator;
    context.push(c.slug.isNotEmpty ? AppRoutes.creatorProfile(c.slug) : AppRoutes.storePage(expert.store.slug));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final store = expert.store;
    final creator = expert.creator;
    final info = expert.calls;
    final canCall = info.online && !info.busy;
    final (status, statusColor) = info.busy
        ? ('In a call', AppColors.warning)
        : info.online
        ? ('Online', const Color(0xFF22C55E))
        : ('Offline', palette.textTertiary);
    final name = creator.name.trim().isEmpty ? store.name : creator.name.trim();
    final category = expert.category.isNotEmpty ? expert.category : creator.category;
    // What the creator says about themselves (title / bio from their profile).
    final headline = creator.title.trim();
    final bio = creator.bio.trim().replaceAll(RegExp(r'\s+'), ' ');
    final rates = [
      if (info.audioEnabled) 'Audio ${_rate(info.audioRate)}',
      if (info.videoEnabled) 'Video ${_rate(info.videoRate)}',
    ].join(' · ');

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProfile(context),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: canCall ? const Color(0xFF22C55E).withValues(alpha: 0.4) : palette.border.withValues(alpha: context.isDark ? 0.55 : 0.7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: canCall ? const Color(0xFF22C55E) : palette.border, width: 2)),
                    child: UserAvatar(initials: creator.initials, imageUrl: creator.avatarUrl.isEmpty ? null : creator.avatarUrl, size: 50),
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(width: 14, height: 14, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, border: Border.all(color: palette.surface, width: 2.5))),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary))),
                        if (creator.verified) ...[
                          const SizedBox(width: 4),
                          const Icon(AppIcons.sealCheck, size: 15, color: AppColors.info),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [if (headline.isNotEmpty) headline else if (category.isNotEmpty) category, status].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: headline.isEmpty && category.isEmpty ? statusColor : palette.textSecondary),
                    ),
                    if (bio.isNotEmpty && bio != headline) ...[
                      const SizedBox(height: 4),
                      Text(bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, height: 1.35, color: palette.textSecondary)),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (creator.rating > 0) ...[
                          const Icon(AppIcons.starFilled, size: 13, color: Color(0xFFF5A524)),
                          const SizedBox(width: 3),
                          Text(
                            '${creator.rating.toStringAsFixed(1)}${creator.reviews > 0 ? ' (${Fmt.compact(creator.reviews)})' : ''}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: palette.textPrimary),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (rates.isNotEmpty)
                          Expanded(child: Text(rates, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: palette.textPrimary))),
                      ],
                    ),
                    if (creator.languages.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('Speaks ${creator.languages.take(3).join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: palette.textTertiary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              canCall
                  ? Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    showRequestCallSheet(context, store: store, info: info);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.phone, size: 15, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Call', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              )
                  : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Profile ›', style: TextStyle(color: palette.textSecondary, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}