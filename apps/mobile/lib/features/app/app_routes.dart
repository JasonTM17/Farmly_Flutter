/// Route paths shared by the router and feature screens.
abstract final class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const signup = '/signup';
  static const verifyEmail = '/verify-email';
  static const emailVerified = '/auth/verified';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/auth/reset-password';
  static const organizations = '/organizations';
  static const invitation = '/invite';

  static const shell = '/shell';
  static const home = '/home';
  static const farm = '/farm';
  static const analytics = '/analytics';
  static const harvest = '/harvest';
  static const profile = '/profile';
  static const livestock = '$farm/livestock';
  static const chat = '/chat';
  static const chatConversation = '/chat/conversation';
  static const syncCenter = '/sync';
  static const zoneDetail = '/farm/zone';
}

String? safeFarmlyReturnTo(String? value) {
  if (value == null || !value.startsWith('/') || value.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  return uri.toString();
}

String farmlyRouteWithReturnTo(String path, String? returnTo) =>
    returnTo == null
    ? path
    : Uri(path: path, queryParameters: {'returnTo': returnTo}).toString();
