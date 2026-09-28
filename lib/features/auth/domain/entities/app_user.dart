import 'package:equatable/equatable.dart';

import '../../../../core/enums/user_role.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.roles,
    required this.onboardingCompleted,
    required this.isEmailVerified,
    required this.walletBalance,
    required this.authProvider,
    this.phone,
    this.avatarUrl,
    this.referralCode,
    this.profileStatus,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final UserRole role;
  final List<UserRole> roles;
  final bool onboardingCompleted;
  final bool isEmailVerified;
  final String? referralCode;

  /// In paise.
  final int walletBalance;

  /// Admin verification of the creator/brand/agency profile. Null for roles
  /// without a profile (fan, admin).
  final VerificationStatus? profileStatus;

  final String authProvider;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        phone,
        avatarUrl,
        role,
        roles,
        onboardingCompleted,
        isEmailVerified,
        referralCode,
        walletBalance,
        profileStatus,
        authProvider,
      ];
}
