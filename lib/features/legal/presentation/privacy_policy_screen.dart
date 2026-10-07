import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/link_opener.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/async_view.dart';

/// Contact address used in these documents.
const _legalEmail = 'support@fanitt.com';

const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Privacy Policy (kept as its own screen for the existing route).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => const LegalScreen(slug: 'privacy-policy');
}

/// Terms of Use.
class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) => const LegalScreen(slug: 'terms-of-use');
}

// ---------------------------------------------------------------------------
// Data (served by the backend: GET /api/legal/:slug)
// ---------------------------------------------------------------------------

class _Block {
  const _Block(this.type, this.text, this.n);

  factory _Block.fromJson(Map<String, dynamic> j) => _Block(J.str(j, 'type', 'p'), J.str(j, 'text'), J.integer(j, 'n'));

  final String type; // p | h | li | ol
  final String text;
  final int n;
}

class _Section {
  const _Section({required this.id, required this.number, required this.title, required this.blocks});

  factory _Section.fromJson(Map<String, dynamic> j) => _Section(
    id: J.str(j, 'id'),
    number: J.str(j, 'number'),
    title: J.str(j, 'title'),
    blocks: J.list(j, 'blocks', _Block.fromJson),
  );

  final String id;
  final String number;
  final String title;
  final List<_Block> blocks;

  String get searchText => '$title ${blocks.map((b) => b.text).join(' ')}'.toLowerCase();
}

class _LegalDoc {
  const _LegalDoc({required this.title, required this.subtitle, required this.updated, required this.effective, required this.intro, required this.sections});

  factory _LegalDoc.fromJson(Map<String, dynamic> j) => _LegalDoc(
    title: J.str(j, 'title'),
    subtitle: J.str(j, 'subtitle'),
    updated: J.str(j, 'updated'),
    effective: J.str(j, 'effective'),
    intro: J.list(j, 'intro', _Block.fromJson),
    sections: J.list(j, 'sections', _Section.fromJson),
  );

  final String title;
  final String subtitle;
  final String updated;
  final String effective;
  final List<_Block> intro;
  final List<_Section> sections;

  int get words => [...intro.map((b) => b.text), for (final s in sections) ...s.blocks.map((b) => b.text)].join(' ').split(RegExp(r'\s+')).length;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// A legal document as tidy, expandable sections with search.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.slug});

  final String slug;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  _LegalDoc? _doc;
  String? _error;
  final _search = TextEditingController();
  final Set<String> _open = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final doc = (await sl<ApiClient>().get('/legal/${widget.slug}', parser: (d) => _LegalDoc.fromJson(J.asMap(d)))).data;
      if (!mounted) return;
      setState(() {
        _doc = doc;
        // First section open so the page doesn't look empty.
        if (doc.sections.isNotEmpty) _open.add(doc.sections.first.id);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    }
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final palette = context.palette;
    final title = doc?.title ?? (widget.slug == 'terms-of-use' ? 'Terms of Use' : 'Privacy Policy');

    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : MessageView(icon: AppIcons.fileText, title: 'Couldn’t load', message: _error!, action: TextButton(onPressed: _load, child: const Text('Try again'))),
      );
    }

    final q = _query.trim().toLowerCase();
    final sections = q.isEmpty ? doc.sections : doc.sections.where((s) => s.searchText.contains(q)).toList();
    final allOpen = sections.every((s) => _open.contains(s.id));
    final minutes = (doc.words / 200).ceil();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14141F), Color(0xFF2A1320)]),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(12)),
                      child: Icon(widget.slug == 'terms-of-use' ? AppIcons.fileText : AppIcons.shieldCheck, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(doc.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
                  ],
                ),
                if (doc.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(doc.subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (doc.updated.isNotEmpty) _MetaChip(icon: AppIcons.calendar, label: 'Updated ${doc.updated}'),
                    if (doc.effective.isNotEmpty) _MetaChip(icon: AppIcons.checkCircle, label: 'Effective ${doc.effective}'),
                    _MetaChip(icon: AppIcons.fileText, label: '${doc.sections.length} sections'),
                    _MetaChip(icon: AppIcons.clock, label: '~$minutes min read'),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms),
          const SizedBox(height: AppSpacing.md),

          // Search + expand all
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search this document',
                    prefixIcon: const Icon(AppIcons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(AppIcons.close, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: () => setState(() {
                  if (allOpen) {
                    _open.removeAll(sections.map((s) => s.id));
                  } else {
                    _open.addAll(sections.map((s) => s.id));
                  }
                }),
                child: Text(allOpen ? 'Collapse all' : 'Expand all', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          if (doc.intro.isNotEmpty && q.isEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: _Blocks(blocks: doc.intro),
            ),

          if (sections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text('Nothing matches “$_query”.', textAlign: TextAlign.center, style: context.text.bodyMedium),
            ),

          // Sections
          for (final s in sections)
            _SectionCard(
              section: s,
              open: q.isNotEmpty || _open.contains(s.id),
              onTap: () => _toggle(s.id),
            ),

          // Contact
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(AppIcons.mail, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Questions about this?', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(_legalEmail, style: context.text.bodySmall),
                    ],
                  ),
                ),
                TextButton(onPressed: () => LinkOpener.open('mailto:$_legalEmail'), child: const Text('Email us')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.sunrise),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.open, required this.onTap});

  final _Section section;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isAnnexure = section.number.toLowerCase().startsWith('annexure');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: open ? AppColors.primary.withValues(alpha: 0.35) : palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: 32),
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: open ? _gradient : null,
                      color: open ? null : palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isAnnexure ? section.number.replaceFirst(RegExp('annexure', caseSensitive: false), '').trim() : section.number,
                      style: TextStyle(color: open ? Colors.white : palette.textSecondary, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isAnnexure) Text('ANNEXURE', style: context.text.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        Text(section.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(AppIcons.chevronDown, size: 20, color: palette.textTertiary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(height: 1, color: palette.border),
                  const SizedBox(height: 12),
                  _Blocks(blocks: section.blocks),
                ],
              ),
            )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Paragraphs, sub-headings, bullets and numbered points.
class _Blocks extends StatelessWidget {
  const _Blocks({required this.blocks});

  final List<_Block> blocks;

  /// Bold a leading defined term ("Account" means …) or a short label before
  /// a colon (Right to Access: …).
  TextSpan _rich(BuildContext context, String text, TextStyle? base) {
    final strong = base?.copyWith(fontWeight: FontWeight.w700, color: context.palette.textPrimary);
    final quoted = RegExp(r'^("[^"]+"(?:\s+and\s+"[^"]+")?)').firstMatch(text);
    if (quoted != null) {
      return TextSpan(style: base, children: [TextSpan(text: quoted.group(1), style: strong), TextSpan(text: text.substring(quoted.end))]);
    }
    final colon = text.indexOf(':');
    if (colon > 0 && colon < 48 && !text.substring(0, colon).contains('.')) {
      return TextSpan(style: base, children: [TextSpan(text: text.substring(0, colon + 1), style: strong), TextSpan(text: text.substring(colon + 1))]);
    }
    return TextSpan(text: text, style: base);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final body = context.text.bodyMedium?.copyWith(color: palette.textPrimary.withValues(alpha: 0.85), height: 1.55, fontSize: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks)
          switch (b.type) {
            'h' => Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(b.text, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
            'li' => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, right: 10),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
                  Expanded(child: Text.rich(_rich(context, b.text, body))),
                ],
              ),
            ),
            'ol' => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 1, right: 10),
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Text('${b.n}', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                  Expanded(child: Text.rich(_rich(context, b.text, body))),
                ],
              ),
            ),
            _ => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text.rich(_rich(context, b.text, body)),
            ),
          },
      ],
    );
  }
}