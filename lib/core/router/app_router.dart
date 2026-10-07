import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/screens/account_screen.dart';
import '../../features/account/presentation/screens/following_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/brands/presentation/brands_screens.dart';
import '../../features/community/data/community_models.dart';
import '../../features/community/presentation/communities_screen.dart';
import '../../features/community/presentation/community_chat_screen.dart';
import '../../features/community/presentation/community_detail_screen.dart';
import '../../features/community/presentation/community_form_screen.dart';
import '../../features/community/presentation/community_members_screen.dart';
import '../../features/community/presentation/community_post_screen.dart';
import '../../features/content/presentation/gifts_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/legal/presentation/privacy_policy_screen.dart';
import '../../features/share/deep_link_landing.dart';
import '../../features/account/presentation/screens/referrals_screen.dart';
import '../../features/agency/presentation/agency_screens.dart';
import '../../features/campaigns/presentation/brand/brand_campaigns_screen.dart';
import '../../features/campaigns/presentation/brand/campaign_editor_screen.dart';
import '../../features/campaigns/presentation/brand/campaign_manage_screen.dart';
import '../../features/campaigns/presentation/creator/campaign_detail_screen.dart';
import '../../features/campaigns/presentation/creator/creator_campaigns_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/conversations_screen.dart';
import '../../features/content/presentation/my_posts_screen.dart';
import '../../features/content/presentation/my_sessions_screen.dart';
import '../../features/creators/presentation/creator_profile_screen.dart';
import '../../features/creators/presentation/creators_screen.dart';
import '../../features/dashboard/presentation/brand_home_screen.dart';
import '../../features/dashboard/presentation/creator_home_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/subscription/presentation/plans_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/cubits/choose_role_cubit.dart';
import '../../features/auth/presentation/cubits/forgot_password_cubit.dart';
import '../../features/auth/presentation/cubits/login_cubit.dart';
import '../../features/auth/presentation/cubits/register_cubit.dart';
import '../../features/auth/presentation/cubits/status_check_cubit.dart';
import '../../features/auth/presentation/screens/choose_role_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/verification_status_screen.dart';
import '../../features/auth/presentation/screens/welcome_screen.dart';
import '../../features/shell/presentation/role_shell.dart';
import '../../features/store/presentation/creator/my_products_screen.dart';
import '../../features/store/presentation/creator/product_editor_screen.dart';
import '../../features/store/presentation/creator/store_entry_screen.dart';
import '../../features/store/presentation/creator/store_sales_screen.dart';
import '../../features/store/presentation/shop/library_screen.dart';
import '../../features/store/presentation/shop/product_detail_screen.dart';
import '../../features/store/presentation/shop/store_discover_screen.dart';
import '../../features/store/presentation/shop/store_page_screen.dart';
import '../../features/store/presentation/shop/products_screen.dart';
import '../../features/store/presentation/affiliate/my_affiliate_screen.dart';
import '../../features/store/presentation/analytics/store_analytics_screen.dart';
import '../../features/store/presentation/call/call_screen.dart';
import '../../features/store/presentation/fanbox/fanbox_received_screen.dart';
import '../../features/store/presentation/meet/meet_detail_screen.dart';
import '../../features/store/presentation/meet/meet_room_screen.dart';
import '../../features/store/presentation/meet/meets_screen.dart';
import '../../features/dashboard/presentation/home_search_screen.dart';
import '../../features/store/presentation/call/call_settings_screen.dart';
import '../../features/store/presentation/live/create_live_screen.dart';
import '../../features/store/presentation/live/live_detail_screen.dart';
import '../../features/store/presentation/live/live_room_screen.dart';
import '../../features/store/presentation/live/my_lives_screen.dart';
import '../enums/user_role.dart';
import '../guards/profile_gate.dart';
import '../di/injection.dart';
import '../storage/onboarding_store.dart';
import '../theme/app_icons.dart';
import 'app_pages.dart';
import 'app_routes.dart';
import 'router_refresh_stream.dart';

class AppRouter {
  AppRouter(this._authBloc);

  final AuthBloc _authBloc;

  static final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  late final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: RouterRefreshStream(_authBloc.stream),
    redirect: _redirect,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => AppPages.fade(state, const SplashScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => AppPages.fade(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        pageBuilder: (context, state) => AppPages.fade(state, const WelcomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => AppPages.push(
          state,
          BlocProvider(create: (_) => LoginCubit(sl()), child: const LoginScreen()),
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (context, state) => AppPages.push(
          state,
          BlocProvider(create: (_) => RegisterCubit(sl()), child: const RegisterScreen()),
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (context, state) => AppPages.push(
          state,
          BlocProvider(create: (_) => ForgotPasswordCubit(sl()), child: const ForgotPasswordScreen()),
        ),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        pageBuilder: (context, state) => AppPages.push(state, ResetPasswordScreen(token: state.uri.queryParameters['token'])),
      ),
      GoRoute(
        path: AppRoutes.chooseRole,
        pageBuilder: (context, state) => AppPages.fade(
          state,
          BlocProvider(create: (_) => ChooseRoleCubit(sl()), child: const ChooseRoleScreen()),
        ),
      ),
      GoRoute(
        path: AppRoutes.verification,
        pageBuilder: (context, state) => AppPages.fade(
          state,
          BlocProvider(create: (_) => StatusCheckCubit(sl()), child: const VerificationStatusScreen()),
        ),
      ),
      _creatorShell(),
      _brandShell(),
      _agencyShell(),
      _fanShell(),
      ..._appPages(),
    ],
  );

  static GoRoute _page(String path, Widget Function(GoRouterState state) build) => GoRoute(
    path: path,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (context, state) => AppPages.push(state, build(state)),
  );

  List<GoRoute> _appPages() => [
    _page(AppRoutes.notifications, (_) => const NotificationsScreen()),
    _page(AppRoutes.plans, (_) => const PlansScreen()),
    _page(AppRoutes.editProfile, (_) => const EditProfileScreen()),
    _page(AppRoutes.wallet, (_) => const WalletScreen()),
    _page(AppRoutes.transactions, (_) => const TransactionsScreen()),
    _page(AppRoutes.referrals, (_) => const ReferralsScreen()),
    _page(AppRoutes.posts, (_) => const MyPostsScreen()),
    _page(AppRoutes.sessions, (_) => const MySessionsScreen()),
    _page(AppRoutes.campaignEditorPath, (s) => CampaignEditorScreen(draftId: s.uri.queryParameters['draft'])),
    _page(AppRoutes.campaignDetailPath, (s) => CampaignDetailScreen(campaignId: s.pathParameters['id']!)),
    _page(AppRoutes.manageCampaignPath, (s) => CampaignManageScreen(campaignId: s.pathParameters['id']!)),
    _page(AppRoutes.chatPath, (s) => ChatScreen(conversationId: s.pathParameters['id']!, args: s.extra is ChatArgs ? s.extra! as ChatArgs : null)),
    _page(AppRoutes.creatorProfilePath, (s) => CreatorProfileScreen(slug: s.pathParameters['slug']!)),
    _page(AppRoutes.brands, (_) => const BrandsScreen()),
    _page(AppRoutes.creatorsDirectory, (_) => const CreatorsScreen()),
    _page(AppRoutes.brandProfilePath, (s) => BrandProfileScreen(slug: s.pathParameters['slug']!)),
    _page(AppRoutes.communities, (_) => const CommunitiesScreen()),
    _page(AppRoutes.communityDetailPath, (s) => CommunityDetailScreen(slug: s.pathParameters['slug']!)),
    _page(AppRoutes.communityPostPath, (s) => CommunityPostScreen(postId: s.pathParameters['postId']!)),
    _page(AppRoutes.communityForm, (s) => CommunityFormScreen(community: s.extra is Community ? s.extra! as Community : null)),
    _page(AppRoutes.communityChat, (s) => s.extra is Community
        ? CommunityChatScreen(community: s.extra! as Community)
        : const CommunitiesScreen()),
    _page(AppRoutes.communityMembers, (s) => s.extra is Community
        ? CommunityMembersScreen(community: s.extra! as Community)
        : const CommunitiesScreen()),
    _page(AppRoutes.feed, (_) => const FeedScreen()),
    _page(AppRoutes.following, (_) => const FollowingScreen()),
    _page(AppRoutes.gifts, (_) => const GiftsScreen()),
    _page(AppRoutes.privacyPolicy, (_) => const PrivacyPolicyScreen()),
    _page(AppRoutes.termsOfUse, (_) => const TermsOfUseScreen()),
    // "Please complete your profile" popup — a see-through page over the current screen.
    GoRoute(
      path: AppRoutes.completeProfile,
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        child: const CompleteProfilePopup(),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    ),
    // Fanitt Store
    _page(AppRoutes.store, (_) => const StoreEntryScreen()),
    _page(AppRoutes.storeProducts, (_) => const MyProductsScreen()),
    _page(AppRoutes.storeProductEditorPath, (s) => ProductEditorScreen(productId: s.uri.queryParameters['id'])),
    _page(AppRoutes.storeSales, (_) => const StoreSalesScreen()),
    _page(AppRoutes.storePagePath, (s) => StorePageScreen(slug: s.pathParameters['slug']!)),
    _page(AppRoutes.storeProductPath, (s) => ProductDetailScreen(productId: s.pathParameters['id']!)),
    _page(AppRoutes.library, (_) => const LibraryScreen()),
    _page(AppRoutes.stores, (_) => const StoreDiscoverScreen(showBack: true)),
    _page(AppRoutes.storeLives, (_) => const MyLivesScreen()),
    _page(AppRoutes.storeLiveNew, (_) => const CreateLiveScreen()),
    _page(AppRoutes.storeCalls, (_) => const CallSettingsScreen()),
    _page(AppRoutes.liveDetailPath, (s) => LiveDetailScreen(liveId: s.pathParameters['id']!, invite: s.uri.queryParameters['invite'])),
    _page(AppRoutes.liveRoom, (s) => s.extra is LiveRoomArgs ? LiveRoomScreen(args: s.extra! as LiveRoomArgs) : const StoreDiscoverScreen(showBack: true)),
    _page(AppRoutes.storeCallPath, (s) => CallScreen(callId: s.pathParameters['id']!)),
    _page(AppRoutes.storeAffiliate, (_) => const MyAffiliateScreen()),
    _page(AppRoutes.storeFanbox, (_) => const FanBoxReceivedScreen()),
    _page(AppRoutes.storeAnalytics, (_) => const StoreAnalyticsScreen()),
    _page(AppRoutes.meets, (_) => const MeetsScreen()),
    _page(AppRoutes.search, (s) => HomeSearchScreen(showFilters: s.uri.queryParameters['filters'] == '1')),
    _page(AppRoutes.savedPosts, (_) => const FeedScreen(savedOnly: true)),
    _page(AppRoutes.postDetailPath, (s) => FeedScreen(postId: s.pathParameters['id'])),
    _page(AppRoutes.products, (s) => ProductsScreen(initialCategory: s.uri.queryParameters['category'])),
    _page(AppRoutes.meetDetailPath, (s) => MeetDetailScreen(meetId: s.pathParameters['id']!)),
    _page(AppRoutes.meetRoom, (s) => s.extra is MeetRoomArgs ? MeetRoomScreen(args: s.extra! as MeetRoomArgs) : const MeetsScreen()),
    // fanitt://open/store — the redirect below sends each role to the right place.
    GoRoute(path: AppRoutes.storeLink, redirect: (_, _) => AppRoutes.splash),
    // Shared links — open the shared item on top of the user's home.
    GoRoute(
      path: AppRoutes.openPath,
      builder: (_, s) => DeepLinkLanding(type: s.pathParameters['type'] ?? '', id: s.pathParameters['id'] ?? ''),
    ),
    // Privacy Policy / Terms — open with or without an account.
    GoRoute(path: AppRoutes.legalPath, builder: (_, s) => LegalScreen(slug: s.pathParameters['slug'] ?? 'privacy-policy')),
  ];

  String? _redirect(BuildContext context, GoRouterState state) {
    final auth = _authBloc.state;
    final location = state.matchedLocation;
    final isPublic = AppRoutes.publicRoutes.contains(location);
    // Legal pages are readable by everyone, signed in or not.
    if (location.startsWith('/legal/')) return null;

    switch (auth) {
      case AuthUnknown() || AuthUnreachable():
        return location == AppRoutes.splash ? null : AppRoutes.splash;

      case AuthUnauthenticated():
      // A shared link before sign-in: remember it and open it after.
        if (location.startsWith('/open/')) PendingDeepLink.value = state.uri.toString();
        // First launch: show the intro screens once before sign-in.
        if (!OnboardingStore.seen) {
          return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
        }
        return isPublic ? null : AppRoutes.welcome;

      case AuthAuthenticated(:final user):
      // New accounts that haven't picked a type yet (Google sign-in
      // creates them as fans) choose one first.
        final needsRole = !user.role.isAppRole || (user.role == UserRole.fan && !user.onboardingCompleted);
        if (needsRole) {
          return location == AppRoutes.chooseRole ? null : AppRoutes.chooseRole;
        }
        if (user.profileStatus?.blocksAccess ?? false) {
          return location == AppRoutes.verification ? null : AppRoutes.verification;
        }
        // A shared link that arrived before sign-in — open it now.
        final pending = PendingDeepLink.value;
        if (pending != null) {
          PendingDeepLink.value = null;
          return pending;
        }
        if (location.startsWith('/open/')) return null;
        // Incomplete profile: main actions open the "complete your profile" popup instead.
        if (needsProfileCompletion(user) && isProfileLockedLocation(location)) {
          return AppRoutes.completeProfile;
        }
        // App link from the website banner: creators to their store, everyone else to shopping.
        if (location == AppRoutes.storeLink) {
          return switch (user.role) {
            UserRole.creator => AppRoutes.store,
            UserRole.fan => AppRoutes.fanHome,
            _ => AppRoutes.stores,
          };
        }
        if (location.startsWith(AppRoutes.appPrefix)) return null;
        if (isPublic || AppRoutes.gateRoutes.contains(location) || !location.startsWith(user.role.routePrefix)) {
          return user.role.homeRoute;
        }
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Role areas. Each tab keeps its own navigation stack.
  // ---------------------------------------------------------------------------

  static StatefulShellBranch _branch(String path, Widget screen) {
    return StatefulShellBranch(
      routes: [GoRoute(path: path, pageBuilder: (context, state) => AppPages.tab(state, screen))],
    );
  }

  static StatefulShellRoute _shell(List<ShellDestination> destinations, List<StatefulShellBranch> branches) {
    return StatefulShellRoute.indexedStack(
      pageBuilder: (context, state, navigationShell) => AppPages.fade(
        state,
        RoleShell(navigationShell: navigationShell, destinations: destinations),
      ),
      branches: branches,
    );
  }

  StatefulShellRoute _creatorShell() => _shell(
    const [
      ShellDestination('Home', AppIcons.home, AppIcons.homeFilled),
      ShellDestination('Feed', AppIcons.feed, AppIcons.feedFilled),
      ShellDestination('Campaigns', AppIcons.campaigns, AppIcons.campaignsFilled),
      ShellDestination('Messages', AppIcons.messages, AppIcons.messagesFilled),
      ShellDestination('Account', AppIcons.account, AppIcons.accountFilled),
    ],
    [
      _branch(AppRoutes.creatorHome, const CreatorHomeScreen()),
      _branch(AppRoutes.creatorFeed, const ProfileGatedTab(title: 'Feed', child: FeedScreen())),
      _branch(AppRoutes.creatorCampaigns, const CreatorCampaignsScreen()),
      _branch(AppRoutes.creatorMessages, const ProfileGatedTab(title: 'Messages', child: ConversationsScreen())),
      _branch(AppRoutes.creatorAccount, const AccountScreen()),
    ],
  );

  StatefulShellRoute _brandShell() => _shell(
    const [
      ShellDestination('Home', AppIcons.home, AppIcons.homeFilled),
      ShellDestination('Campaigns', AppIcons.campaigns, AppIcons.campaignsFilled),
      ShellDestination('Creators', AppIcons.creators, AppIcons.creatorsFilled),
      ShellDestination('Messages', AppIcons.messages, AppIcons.messagesFilled),
      ShellDestination('Account', AppIcons.account, AppIcons.accountFilled),
    ],
    [
      _branch(AppRoutes.brandHome, const BrandHomeScreen()),
      _branch(AppRoutes.brandCampaigns, const BrandCampaignsScreen()),
      _branch(AppRoutes.brandCreators, const ProfileGatedTab(title: 'Creators', child: CreatorsScreen())),
      _branch(AppRoutes.brandMessages, const ProfileGatedTab(title: 'Messages', child: ConversationsScreen())),
      _branch(AppRoutes.brandAccount, const AccountScreen()),
    ],
  );

  StatefulShellRoute _fanShell() => _shell(
    const [
      ShellDestination('Store', AppIcons.store, AppIcons.storeFilled),
      ShellDestination('Feed', AppIcons.feed, AppIcons.feedFilled),
      ShellDestination('Library', AppIcons.library, AppIcons.libraryFilled),
      ShellDestination('Messages', AppIcons.messages, AppIcons.messagesFilled),
      ShellDestination('Account', AppIcons.account, AppIcons.accountFilled),
    ],
    [
      _branch(AppRoutes.fanHome, const StoreDiscoverScreen()),
      _branch(AppRoutes.fanFeed, const FeedScreen()),
      _branch(AppRoutes.fanLibrary, const LibraryScreen(showBack: false)),
      _branch(AppRoutes.fanMessages, const ConversationsScreen()),
      _branch(AppRoutes.fanAccount, const AccountScreen()),
    ],
  );

  StatefulShellRoute _agencyShell() => _shell(
    const [
      ShellDestination('Dashboard', AppIcons.dashboard, AppIcons.dashboardFilled),
      ShellDestination('Network', AppIcons.network, AppIcons.networkFilled),
      ShellDestination('Earnings', AppIcons.wallet, AppIcons.walletFilled),
      ShellDestination('Account', AppIcons.account, AppIcons.accountFilled),
    ],
    [
      _branch(AppRoutes.agencyHome, const AgencyHomeScreen()),
      _branch(AppRoutes.agencyNetwork, const AgencyNetworkScreen()),
      _branch(AppRoutes.agencyEarnings, const WalletScreen(title: 'Earnings')),
      _branch(AppRoutes.agencyAccount, const AccountScreen()),
    ],
  );
}