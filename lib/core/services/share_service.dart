import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_icons.dart';

/// Links that open a particular screen in the app:
///   https://fanitt.com/open/<type>/<id-or-slug>
/// Installed app → opens straight to it (after sign-in if needed).
/// Not installed → the website page offers the app / Play Store.
abstract final class ShareLinks {
  static const String site = 'https://fanitt.com';
  static const String playStore = 'https://play.google.com/store/apps/details?id=fanitt.comapp.fanittapp';

  static String open(String type, String id) => '$site/open/$type/${Uri.encodeComponent(id)}';
}

/// A ready-to-send share: the text (with the link) and an email subject.
class ShareMessage {
  const ShareMessage({required this.subject, required this.text});

  final String subject;
  final String text;
}

/// Friendly, ready-made messages for everything on Fanitt. Each has an
/// "it's mine" version for owners and a "check this out" version for others.
abstract final class ShareService {
  static String _money(int paise) => paise <= 0 ? 'Free' : NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(paise / 100);

  static String _clip(String text, [int max = 110]) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= max ? t : '${t.substring(0, max).trimRight()}…';
  }

  /// Opens the system share sheet (WhatsApp, Instagram, X, Telegram, …).
  static Future<void> send(BuildContext context, ShareMessage message) async {
    HapticFeedback.selectionClick();
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      message.text,
      subject: message.subject,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  static ShareMessage campaign({required String id, required String title, required String brand, required bool isPaid, required int pay, required String location, bool mine = false}) {
    final link = ShareLinks.open('campaign', id);
    final offer = isPaid ? '💰 ${_money(pay)} per creator' : '🎁 Barter collaboration';
    return ShareMessage(
      subject: '$brand is hiring creators on Fanitt',
      text: mine
          ? '🚀 We’re hiring creators on Fanitt!\n\n“$title”\n$offer\n📍 $location\n\nApply here 👉 $link'
          : '🚀 $brand is looking for creators on Fanitt!\n\n“$title”\n$offer\n📍 $location\n\nApply before spots fill up 👉 $link',
    );
  }

  static ShareMessage session({required String id, required String title, required String host, DateTime? when, required int price, bool mine = false}) {
    final link = ShareLinks.open('session', id);
    final date = when == null ? '' : '\n📅 ${DateFormat('EEE, d MMM · h:mm a').format(when.toLocal())}';
    final cost = price <= 0 ? '🎟️ Free to join' : '🎟️ ${_money(price)}';
    return ShareMessage(
      subject: '“$title” — live on Fanitt',
      text: mine
          ? '🎥 I’m hosting a live session on Fanitt!\n\n“$title”$date\n$cost\n\nSave your seat 👉 $link'
          : '🎥 Join “$title” with $host — a live session on Fanitt$date\n$cost\n\nBook your seat 👉 $link',
    );
  }

  static ShareMessage brand({required String slug, required String name, String industry = '', bool mine = false}) {
    final link = ShareLinks.open('brand', slug);
    final what = industry.isEmpty ? '' : ' · $industry';
    return ShareMessage(
      subject: '$name on Fanitt',
      text: mine
          ? '🏢 $name is on Fanitt$what — we collaborate with creators here.\n\nSee our campaigns 👉 $link'
          : '🏢 Check out $name on Fanitt$what — they work with creators.\n\n👉 $link',
    );
  }

  static ShareMessage community({required String slug, required String name, int members = 0, bool mine = false}) {
    final link = ShareLinks.open('community', slug);
    final count = members > 0 ? ' — ${NumberFormat.compact().format(members)} members' : '';
    return ShareMessage(
      subject: '$name community on Fanitt',
      text: mine
          ? '💬 Come join my community “$name” on Fanitt$count!\n\n👉 $link'
          : '💬 Join the “$name” community on Fanitt$count.\n\n👉 $link',
    );
  }

  static ShareMessage product({required String id, required String title, required String store, required int price, String category = '', bool mine = false}) {
    final link = ShareLinks.open('product', id);
    final kind = category.isEmpty ? 'product' : category.toLowerCase();
    return ShareMessage(
      subject: '$title — on Fanitt',
      text: mine
          ? '✨ My new $kind is live on Fanitt!\n\n“$title”\n💳 ${_money(price)} · instant download\n\nGet it here 👉 $link'
          : '✨ “$title” by $store\n💳 ${_money(price)} · instant download on Fanitt\n\n👉 $link',
    );
  }

  static ShareMessage store({required String slug, required String name, String tagline = '', bool mine = false}) {
    final link = ShareLinks.open('store', slug);
    final line = tagline.isEmpty ? 'Courses, guides, templates & more' : _clip(tagline, 90);
    return ShareMessage(
      subject: '$name — Fanitt Store',
      text: mine
          ? '🛍️ My store is live on Fanitt!\n$line\n\nShop now 👉 $link'
          : '🛍️ Visit $name on Fanitt\n$line\n\n👉 $link',
    );
  }

  static ShareMessage creator({required String slug, required String name, String category = '', bool mine = false}) {
    final link = ShareLinks.open('creator', slug);
    final what = category.isEmpty ? '' : ' · $category';
    return ShareMessage(
      subject: '$name on Fanitt',
      text: mine
          ? '⭐ Find me on Fanitt$what — follow me and let’s collaborate!\n\n👉 $link'
          : '⭐ Discover $name on Fanitt$what\n\n👉 $link',
    );
  }

  static ShareMessage post({required String id, required String creator, String caption = '', bool mine = false}) {
    final link = ShareLinks.open('post', id);
    final quote = caption.trim().isEmpty ? '' : '\n“${_clip(caption)}”\n';
    return ShareMessage(
      subject: mine ? 'My new post on Fanitt' : '$creator on Fanitt',
      text: mine ? '📸 New post on my Fanitt profile!$quote\n👉 $link' : '📸 $creator posted on Fanitt$quote\n👉 $link',
    );
  }

  static ShareMessage app() => const ShareMessage(
    subject: 'Join me on Fanitt',
    text: '🚀 I’m on Fanitt — where creators, brands and fans work together.\n\nFind paid campaigns, open your own store, go live and earn.\n\nDownload the app 👉 ${ShareLinks.playStore}',
  );

  /// Refer & earn invite with the user's own code.
  static ShareMessage referral(String code) => ShareMessage(
    subject: 'Your Fanitt invite from me 🎁',
    text: '🎁 You’re invited to Fanitt!\n\n'
        'India’s app where creators, brands and fans work together:\n'
        '💼 Get paid brand campaigns\n'
        '🛍️ Open your own Fanitt Store\n'
        '🎥 Host 1:1 meets with your fans\n'
        '🔒 Every payment protected until the work is done\n\n'
        '✨ Use my code: *$code*\n'
        '(enter it when you sign up)\n\n'
        'Download now 👉 ${ShareLinks.playStore}',
  );
}

/// Small round share button for cards and app bars.
class ShareIconButton extends StatelessWidget {
  const ShareIconButton({super.key, required this.message, this.onDark = false, this.size = 34});

  /// Built only when tapped (so cards don't format text for nothing).
  final ShareMessage Function() message;
  final bool onDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Material(
      color: onDark ? Colors.black.withValues(alpha: 0.4) : Colors.transparent,
      shape: const CircleBorder(),
      child: Builder(
        builder: (inner) => InkWell(
          customBorder: const CircleBorder(),
          onTap: () => ShareService.send(inner, message()),
          child: SizedBox(width: size, height: size, child: Icon(AppIcons.share, size: size * 0.5, color: color)),
        ),
      ),
    );
  }
}