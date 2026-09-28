import 'package:flutter/foundation.dart';

/// Single mute switch shared by every video in the app.
/// Muting/unmuting one video mutes/unmutes all of them.
abstract final class VideoMuteController {
  static final ValueNotifier<bool> muted = ValueNotifier<bool>(true);

  static void toggle() => muted.value = !muted.value;
}