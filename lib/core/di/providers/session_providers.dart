import 'package:dawarich/core/di/providers/user_providers.dart';
import 'package:dawarich/core/domain/models/user.dart';
import 'package:dawarich/features/auth/application/repositories/user_repository_interfaces.dart';
import 'package:dawarich/features/auth/application/usecases/validate_user_usecase.dart';
import 'package:dawarich_android_user_module/dawarich_android_user_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final validateUserUseCaseProvider =
    FutureProvider<ValidateUserUseCase>((ref) async {
  final IUserRepository userRepository =
      await ref.watch(userRepositoryProvider.future);
  return ValidateUserUseCase(userRepository);
});

final sessionBoxProvider =
    FutureProvider<DawarichAndroidUserModule<User>>((ref) async {
  ref.keepAlive();

  final validateUser = await ref.watch(validateUserUseCaseProvider.future);

  final box = await DawarichAndroidUserModule.create<User>(
    encrypt: false,
    toJson: (user) => user.toJson(),
    fromJson: (json) => User.fromJson(json),
    isValidUser: (user) => validateUser(user),
  );

  return box;
});

/// Holds the currently authenticated user.
/// Set by AuthGuard when navigating to protected routes.
/// In protected contexts, this is guaranteed to be non-null.
final authenticatedUserProvider =
    NotifierProvider<AuthenticatedUserNotifier, User?>(
        () => AuthenticatedUserNotifier());

class AuthenticatedUserNotifier extends Notifier<User?> {
  @override
  User? build() => null;

  void setUser(User? user) {
    state = user;
  }
}

/// Guaranteed non-null user in guarded routes.
/// If this throws, your app state is inconsistent (bug), not "user forgot to login".
final currentUserProvider = Provider<User>((ref) {
  final user = ref.watch(authenticatedUserProvider);
  if (user == null) {
    throw StateError(
      'currentUserProvider: User is required but authenticatedUserProvider is null. '
      'This should be impossible inside guarded routes.',
    );
  }
  return user;
});

/// Convenience provider for the local DB user id.
/// Adjust the field name if your User model uses something else than `id`.
final currentUserIdProvider = Provider<int>((ref) {
  final user = ref.watch(currentUserProvider);
  return user.id;
});

/// Async session user (nullable).
/// Works in background bootstraps because it reads from session storage, not router state.
final sessionUserProvider = FutureProvider<User?>((ref) async {
  final DawarichAndroidUserModule<User> box =
      await ref.watch(sessionBoxProvider.future);
  return box.getUser();
});

/// Convenience: local DB user id, nullable, from session.
/// Background jobs can use this and skip when null.
final sessionUserIdProvider = FutureProvider<int?>((ref) async {
  final user = await ref.watch(sessionUserProvider.future);
  return user?.id;
});

/// Tracelet background jobs resolve the user id from session state instead of UI state.
final traceletBackgroundUserIdProvider = FutureProvider<int?>((ref) async {
  return ref.watch(sessionUserIdProvider.future);
});
