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

  // Fan tabs
  static const String fanHome = '/fan/home';
  static const String fanFeed = '/fan/feed';
  static const String fanLibrary = '/fan/library';
  static const String fanMessages = '/fan/messages';
  static const String fanAccount = '/fan/account';

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
  static const String communityDetailPath = '/app/c/:slug';
  static const String communityPostPath = '/app/c-post/:postId';
  static const String communityForm = '/app/community-form';
  static const String communityChat = '/app/community-chat';
  static const String communityMembers = '/app/community-members';
  static const String feed = '/app/feed';
  static const String following = '/app/following';
  static const String gifts = '/app/gifts';
  static const String privacyPolicy = '/app/privacy-policy';
  static const String termsOfUse = '/app/terms';

  /// Legal pages that open with or without an account (e.g. from sign-up).
  static const String legalPath = '/legal/:slug';
  static String legal(String slug) => '/legal/$slug';

  /// "Please complete your profile" popup (see core/guards/profile_gate.dart).
  static const String completeProfile = '/app/complete-profile';

  // Fanitt Store
  static const String store = '/app/store';
  static const String storeProducts = '/app/store/products';
  static const String storeProductEditorPath = '/app/store/product-editor';
  static const String storeSales = '/app/store/sales';
  static const String storePagePath = '/app/s/:slug';
  static const String storeProductPath = '/app/sp/:id';
  static const String library = '/app/library';
  static const String stores = '/app/stores';
  static const String storeLives = '/app/store/lives';
  static const String storeLiveNew = '/app/store/lives/new';
  static const String storeCalls = '/app/store/calls';
  static const String liveDetailPath = '/app/live/:id';
  static const String liveRoom = '/app/live-room';
  static const String storeCallPath = '/app/call/:id';
  static const String storeAffiliate = '/app/store/affiliate';
  static const String storeFanbox = '/app/store/fanbox';
  static const String storeAnalytics = '/app/store/analytics';
  static const String meets = '/app/meets';
  static const String search = '/app/search';
  static const String savedPosts = '/app/saved';

  /// One post (opened from a shared link).
  static const String postDetailPath = '/app/post/:id';
  static String postDetail(String id) => '/app/post/$id';

  /// Shared links: https://fanitt.com/open/<type>/<id>
  static const String openPath = '/open/:type/:id';
  static const String products = '/app/products';
  static const String meetDetailPath = '/app/meet/:id';
  static const String meetRoom = '/app/meet-room';

  /// Target of the `fanitt://open/store` link (website banner).
  static const String storeLink = '/store';

  static String campaignDetail(String id) => '/app/campaigns/$id';
  static String manageCampaign(String id) => '/app/manage/$id';
  static String chat(String id) => '/app/chat/$id';
  static String creatorProfile(String slug) => '/app/creators/$slug';
  static String brandProfile(String slug) => '/app/brands/$slug';
  static String communityDetail(String slugOrId) => '/app/c/$slugOrId';
  static String communityPost(String postId) => '/app/c-post/$postId';
  static String storePage(String slug) => '/app/s/$slug';
  static String storeProduct(String id) => '/app/sp/$id';
  static String liveDetail(String id, {String? invite}) => invite == null || invite.isEmpty ? '/app/live/$id' : '/app/live/$id?invite=${Uri.encodeQueryComponent(invite)}';
  static String storeCall(String id) => '/app/call/$id';
  static String meetDetail(String id) => '/app/meet/$id';
  static String storeProductEditor([String? productId]) =>
      productId == null ? storeProductEditorPath : '$storeProductEditorPath?id=$productId';
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
    UserRole.fan => AppRoutes.fanHome,
    _ => AppRoutes.chooseRole,
  };

  /// Every tab route inside a role's area starts with this.
  String get routePrefix => '/$value/';
}