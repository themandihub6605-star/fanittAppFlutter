import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/data/services/google_auth_service.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/agency/data/agency_repository.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/brands/data/brands_repository.dart';
import '../../features/campaigns/data/campaign_repository.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/common/data/categories_repository.dart';
import '../../features/community/data/community_repository.dart';
import '../../features/content/data/content_repository.dart';
import '../../features/creators/data/creators_repository.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/reviews/data/review_repository.dart';
import '../../features/subscription/data/subscription_repository.dart';
import '../../features/wallet/data/wallet_repository.dart';
import '../network/api_client.dart';
import '../network/session_events.dart';
import '../services/media_picker.dart';
import '../../features/store/data/store_repository.dart';
import '../services/app_update_service.dart';
import '../services/payment_service.dart';
import '../services/push_service.dart';
import '../services/socket_service.dart';
import '../storage/token_storage.dart';

final GetIt sl = GetIt.instance;

Future<void> configureDependencies() async {
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final prefs = await SharedPreferences.getInstance();
  await _clearKeychainOnFreshInstall(prefs, secureStorage);

  sl
  // Core
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerSingleton<FlutterSecureStorage>(secureStorage)
    ..registerLazySingleton<TokenStorage>(() => TokenStorage(sl()))
    ..registerLazySingleton<SessionEvents>(SessionEvents.new)
    ..registerLazySingleton<ApiClient>(() => ApiClient(storage: sl(), sessionEvents: sl()))

  // Auth
    ..registerLazySingleton<GoogleAuthService>(() => GoogleAuthService(FirebaseAuth.instance))
    ..registerLazySingleton<AuthRemoteDataSource>(() => AuthRemoteDataSource(sl()))
    ..registerLazySingleton<AuthRepository>(
          () => AuthRepositoryImpl(remote: sl(), tokens: sl(), google: sl()),
    )
    ..registerLazySingleton<AuthBloc>(() => AuthBloc(repository: sl(), sessionEvents: sl(), socket: sl(), push: sl()))

  // Services
    ..registerLazySingleton<PaymentService>(PaymentService.new)
    ..registerLazySingleton<MediaPicker>(MediaPicker.new)
    ..registerLazySingleton<SocketService>(() => SocketService(sl()))
    ..registerLazySingleton<PushService>(() => PushService(sl()))
    ..registerLazySingleton<AppUpdateService>(AppUpdateService.new)
    ..registerLazySingleton<StoreRepository>(() => StoreRepository(sl()))

  // Features
    ..registerLazySingleton<CategoriesRepository>(() => CategoriesRepository(sl()))
    ..registerLazySingleton<ProfileRepository>(() => ProfileRepository(sl()))
    ..registerLazySingleton<CampaignRepository>(() => CampaignRepository(sl()))
    ..registerLazySingleton<ChatRepository>(() => ChatRepository(sl()))
    ..registerLazySingleton<NotificationRepository>(() => NotificationRepository(sl()))
    ..registerLazySingleton<WalletRepository>(() => WalletRepository(sl()))
    ..registerLazySingleton<SubscriptionRepository>(() => SubscriptionRepository(sl(), sl()))
    ..registerLazySingleton<ContentRepository>(() => ContentRepository(sl()))
    ..registerLazySingleton<CreatorsRepository>(() => CreatorsRepository(sl(), sl()))
    ..registerLazySingleton<DashboardRepository>(() => DashboardRepository(sl()))
    ..registerLazySingleton<AgencyRepository>(() => AgencyRepository(sl()))
    ..registerLazySingleton<BrandsRepository>(() => BrandsRepository(sl()))
    ..registerLazySingleton<CommunityRepository>(() => CommunityRepository(sl()))
    ..registerLazySingleton<ReviewRepository>(() => ReviewRepository(sl()));
}

/// iOS keeps Keychain items after an app is deleted. Without this, a
/// reinstall would silently sign the previous user back in.
Future<void> _clearKeychainOnFreshInstall(SharedPreferences prefs, FlutterSecureStorage storage) async {
  const key = 'fanitt.hasLaunchedBefore';
  if (prefs.getBool(key) ?? false) return;
  await storage.deleteAll();
  await prefs.setBool(key, true);
}