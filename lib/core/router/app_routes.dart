import '../enums/user_role.dart';

abstract final class AppRoutes {
  // Session
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String chooseRole = '/choose-role';
  static const String verification = '/verification';

  // Creator tabs
  static const String creatorHome = '/creator/home';
  static const String creatorFeed = '/creator/feed';
  static const String creatorCampaigns = '/creator/campaigns';
  static const String creatorMessages = '/creator/messages';
  static const String creatorAccount = '/creator/account';

  // Brand tabs
  static const String brandHome = '/brand/home';
  static const String brandCampaigns = '/brand/campaigns';
  static const String brandCreators = '/brand/creators';
  static const String brandMessages = '/brand/messages';
  static const String brandAccount = '/brand/account';

  // Agency tabs
  static const String agencyHome = '/agency/home';
  static const String agencyNetwork = '/agency/network';
  static const String agencyEarnings = '/agency/earnings';
  static const String agencyAccount = '/agency/account';

  /// Full-screen pages pushed over the tabs. Every role may open them.
  static const String appPrefix = '/app/';

  static const String notifications = '/app/notifications';
  static const String plans = '/app/plans';
  static const String editProfile = '/app/profile/edit';
  static const String wallet = '/app/wallet';
  static const String transactions = '/app/transactions';
  static const String referrals = '/app/referrals';
  static const String posts = '/app/posts';
  static const String sessions = '/app/sessions';
  static const String campaignEditorPath = '/app/campaign-editor';
  static const String campaignDetailPath = '/app/campaigns/:id';
  static const String manageCampaignPath = '/app/manage/:id';
  static const String chatPath = '/app/chat/:id';
  static const String creatorProfilePath = '/app/creators/:slug';
  static const String brandProfilePath = '/app/brands/:slug';
  static const String brands = '/app/brands';
  static const String creatorsDirectory = '/app/creators';
  static const String communities = '/app/communities';
  static const String feed = '/app/feed';
  static const String following = '/app/following';
  static const String gifts = '/app/gifts';
  static const String privacyPolicy = '/app/privacy-policy';

  static String campaignDetail(String id) => '/app/campaigns/$id';
  static String manageCampaign(String id) => '/app/manage/$id';
  static String chat(String id) => '/app/chat/$id';
  static String creatorProfile(String slug) => '/app/creators/$slug';
  static String brandProfile(String slug) => '/app/brands/$slug';
  static String campaignEditor({String? draftId}) =>
      draftId == null ? campaignEditorPath : '$campaignEditorPath?draft=$draftId';

  static const Set<String> publicRoutes = {welcome, login, register, forgotPassword, resetPassword};
  static const Set<String> gateRoutes = {splash, chooseRole, verification};
}

extension UserRoleRouting on UserRole {
  String get homeRoute => switch (this) {
    UserRole.creator => AppRoutes.creatorHome,
    UserRole.brand => AppRoutes.brandHome,
    UserRole.agency => AppRoutes.agencyHome,
    _ => AppRoutes.chooseRole,
  };

  /// Every tab route inside a role's area starts with this.
  String get routePrefix => '/$value/';
}