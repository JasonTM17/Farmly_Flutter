enum FarmlyAuthFailureCode {
  invalidCredentials,
  emailNotVerified,
  rateLimited,
  invalidLink,
  unavailable,
  offlineLeaseExpired,
  unexpected,
  signOutUnconfirmed,
}

final class FarmlyAuthFailure implements Exception {
  const FarmlyAuthFailure(this.code);

  final FarmlyAuthFailureCode code;
}

final class FarmlyAuthUser {
  const FarmlyAuthUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;
}

final class FarmlyAuthSession {
  const FarmlyAuthSession({required this.user});

  final FarmlyAuthUser user;
}
