import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';

/// Shared layout for every auth screen: back button, animated title block,
/// scrollable content, and a footer that sits at the bottom on tall screens
/// and scrolls with the content on short ones.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.onBack,
    this.showBack = true,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onBack;
  final bool showBack;

  /// Optional widget above the title (e.g. the logo).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final canGoBack = showBack && (onBack != null || Navigator.of(context).canPop());

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 56,
        leading: canGoBack
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(AppIcons.back),
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xs,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(height: AppSpacing.xl)],
                    AnimatedSwitcher(
                      duration: AppDurations.normal,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topLeft,
                        children: [...previous, if (current != null) current],
                      ),
                      child: _Header(key: ValueKey(title), title: title, subtitle: subtitle),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    child
                        .animate()
                        .fadeIn(duration: 380.ms, delay: 80.ms)
                        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
                    if (footer != null) ...[
                      const Spacer(),
                      const SizedBox(height: AppSpacing.xl),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle!, style: context.text.bodyMedium?.copyWith(fontSize: 15)),
        ],
      ],
    );
  }
}
