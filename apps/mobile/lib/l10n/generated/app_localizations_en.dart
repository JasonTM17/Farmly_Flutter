// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Farmly';

  @override
  String get appSubtitle => 'Your farm, thoughtfully managed';

  @override
  String greetingMorning(String name) {
    return 'Good morning, $name';
  }

  @override
  String greetingNoon(String name) {
    return 'Good afternoon, $name';
  }

  @override
  String greetingAfternoon(String name) {
    return 'Good afternoon, $name';
  }

  @override
  String greetingEvening(String name) {
    return 'Good evening, $name';
  }

  @override
  String get loading => 'Loading';

  @override
  String get homeTab => 'Home';

  @override
  String get farmTab => 'My Farm';

  @override
  String get analyticsTab => 'Insights';

  @override
  String get harvestTab => 'Harvest';

  @override
  String get profileTab => 'Profile';

  @override
  String get back => 'Back';

  @override
  String get retry => 'Try again';

  @override
  String get continueLabel => 'Continue';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Continue';

  @override
  String get loginTitle => 'Sign in to Farmly';

  @override
  String get loginDescription => 'Welcome back to your farm.';

  @override
  String get emailLabel => 'Email address';

  @override
  String get passwordLabel => 'Password';

  @override
  String get fullNameLabel => 'Full name';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get keepSignedIn => 'Keep me signed in on this device';

  @override
  String get signIn => 'Sign in';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get createAccountPrompt => 'New to Farmly? Create an account';

  @override
  String get haveAccountPrompt => 'Already have an account? Sign in';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get emailRequired => 'Enter your email address.';

  @override
  String get emailInvalid => 'Enter a valid email address.';

  @override
  String get nameRequired => 'Enter your name.';

  @override
  String get passwordRequired => 'Enter your password.';

  @override
  String get passwordTooShort => 'Use at least 8 characters.';

  @override
  String get passwordTooLong => 'Use no more than 128 characters.';

  @override
  String get passwordsDoNotMatch => 'The passwords do not match.';

  @override
  String get invalidCredentials =>
      'Email or password is incorrect. Check them and try again.';

  @override
  String get emailNotVerified =>
      'Verify your email before signing in. Check your inbox for the link.';

  @override
  String get rateLimited => 'Too many attempts. Wait a little, then try again.';

  @override
  String get authUnavailable =>
      'We can’t reach Farmly right now. Check your connection and try again.';

  @override
  String get authUnexpected => 'We couldn’t complete that request. Try again.';

  @override
  String get signOutUnconfirmed =>
      'You are signed out on this device, but Farmly could not confirm server sign-out.';

  @override
  String get createAccountTitle => 'Create your account';

  @override
  String get createAccount => 'Create account';

  @override
  String get creatingAccount => 'Creating account…';

  @override
  String get verifyEmailTitle => 'Check your email';

  @override
  String get verifyEmailBody =>
      'If this address can be registered, Farmly sent a verification link. Open it, then return here to sign in.';

  @override
  String get resendVerification => 'Send the verification link again';

  @override
  String get verificationSent =>
      'If the address is eligible, a new link is on its way.';

  @override
  String get verifiedTitle => 'Email verified';

  @override
  String get verifiedBody => 'Your email is ready. Sign in to continue.';

  @override
  String get invalidLinkTitle => 'This link can’t be used';

  @override
  String get invalidLinkBody =>
      'It may have expired or already been used. Request a new link and try again.';

  @override
  String get forgotPasswordTitle => 'Reset your password';

  @override
  String get forgotPasswordBody =>
      'Enter your email. If an account can be found, we’ll send a reset link.';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get resetRequested =>
      'If an account can be found, a reset link is on its way.';

  @override
  String get resetPasswordTitle => 'Choose a new password';

  @override
  String get saveNewPassword => 'Save new password';

  @override
  String get passwordResetComplete =>
      'Your password has been changed. Sign in with the new password.';

  @override
  String get sessionUnavailableTitle => 'Can’t verify your session';

  @override
  String get sessionUnavailableBody =>
      'Connect to the internet to check your session, or sign in again.';

  @override
  String get offlineLeaseExpiredBody =>
      'Your offline access period has ended. Connect to the internet and sign in to continue. Saved work stays protected on this device.';

  @override
  String get resetLinkInstructions =>
      'Choose a new password for your Farmly account.';

  @override
  String get changeScope => 'Change scope';

  @override
  String get farmPickerTitle => 'Choose a farm';

  @override
  String get organizationPickerTitle => 'Choose an organization';

  @override
  String get farmPickerOrganizationHint =>
      'To change organization, open Profile → Organizations.';

  @override
  String farmRowSemantics(String farm, String organization) {
    return 'Farm $farm, organization $organization';
  }

  @override
  String farmIdentifier(String farmId) {
    return 'Farm ID: $farmId';
  }

  @override
  String farmScopeSummary(String organization, String farm) {
    return '$organization · $farm';
  }

  @override
  String get sampleDataNotice =>
      'Preview data only. These figures are examples, not live farm records.';

  @override
  String get sampleDataLabel => 'Sample data';

  @override
  String get noSelectedFarm => 'No farm selected';

  @override
  String permissionBannerSemantics(String message) {
    return 'Permission notice: $message';
  }

  @override
  String organizationRowSemantics(String name) {
    return 'Organization $name';
  }

  @override
  String get openNotifications => 'Open notifications';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmpty => 'No notifications yet.';

  @override
  String get notificationUnreadSemantics => 'Unread';

  @override
  String get notificationReadSemantics => 'Read';

  @override
  String get notificationPermissionMessage =>
      'Notifications are turned off. Enable them in system settings to receive alerts outside Farmly.';

  @override
  String get notificationPermissionAction => 'How to enable';

  @override
  String get notificationGuideTitle => 'Turn on Farmly notifications';

  @override
  String get notificationGuideBody =>
      '1. Open your phone’s Settings app.\n2. Choose Apps → Farmly.\n3. Open Notifications and turn on Allow notifications.\n4. Return to Farmly to receive alerts outside the app.';

  @override
  String get understood => 'Got it';

  @override
  String get loadErrorTitle => 'Couldn’t load data';

  @override
  String get loadErrorBody =>
      'There was a problem loading this data. It has not been saved to this device. Try again or change the scope.';

  @override
  String get permissionDeniedTitle => 'You don’t have permission to view this';

  @override
  String get offlineNoDate => 'Offline — showing data saved on this device.';

  @override
  String offlineWithDate(String asOf) {
    return 'Offline — showing the device copy (data through $asOf).';
  }

  @override
  String offlineSemantics(String asOf) {
    return 'No connection, showing saved data through $asOf.';
  }

  @override
  String get offlineSemanticsNoDate => 'No connection, showing saved data.';

  @override
  String conflictBannerSemantics(int count) {
    return '$count items need conflict resolution. Open Sync Center.';
  }

  @override
  String conflictBannerBody(int count) {
    return '$count conflicting records need your attention.';
  }

  @override
  String get demoState => 'Demo state';

  @override
  String demoStateCurrent(String state) {
    return 'Demo state: $state';
  }

  @override
  String get demoStateSwitchSemantics => 'Change this screen’s demo state';

  @override
  String demoStateSelected(String state, String selected) {
    return 'Switch screen to $state$selected';
  }

  @override
  String get demoSelectedSuffix => ', selected';

  @override
  String get demoSuccess => 'Success';

  @override
  String get demoLoading => 'Loading';

  @override
  String get demoEmpty => 'Empty';

  @override
  String get demoRecoverableError => 'Recoverable error';

  @override
  String get demoOffline => 'Offline';

  @override
  String get demoPermissionDenied => 'Permission denied';

  @override
  String get demoPendingConflict => 'Conflict pending';

  @override
  String get homePermissionDeniedBody =>
      'Your account can’t view this farm. Change scope or contact the farm owner.';

  @override
  String get homeEmptyTitle => 'Your farm is ready to grow';

  @override
  String get homeEmptyBody =>
      'Add your first growing zone or livestock area to track work and production.';

  @override
  String get switchFarm => 'Change farm';

  @override
  String get weatherSunny => 'Sunny';

  @override
  String get windLight => 'Light wind';

  @override
  String weatherHumidity(int humidity) {
    return 'Humidity $humidity%';
  }

  @override
  String weatherSemantics(
    String condition,
    int temperature,
    int humidity,
    String wind,
    String source,
    String asOf,
  ) {
    return '$condition, $temperature degrees C, humidity $humidity%, $wind; $source $asOf.';
  }

  @override
  String get todayForecastSource => 'today’s forecast';

  @override
  String get savedDataSource => 'saved data';

  @override
  String asOfSource(String asOf, String source) {
    return 'Data through $asOf · source $source';
  }

  @override
  String get operationalHealth => 'Operations health';

  @override
  String get operationalHealthEstimate =>
      'Estimated from today’s feeding progress.';

  @override
  String get operationalHealthUnknown =>
      'Not enough data today to estimate operations health.';

  @override
  String get unknown => 'Unknown';

  @override
  String get todayTasks => 'Tasks today';

  @override
  String tasksDoneSemantics(int done, int total) {
    return '$done of $total tasks';
  }

  @override
  String get livestock => 'Livestock';

  @override
  String get animalUnit => 'animals';

  @override
  String get zones => 'Zones';

  @override
  String get zoneUnit => 'zones';

  @override
  String get currentHarvest => 'Harvest this period';

  @override
  String harvestValueSemantics(String amount) {
    return '$amount kilograms';
  }

  @override
  String pendingHarvestAmount(String amount) {
    return ', plus $amount kilograms waiting to sync';
  }

  @override
  String get askFarmlyAi => 'Ask Farmly AI';

  @override
  String get askFarmlyAiSemantics =>
      'Ask Farmly AI. Open the read-only farm assistant.';

  @override
  String get organizationTitle => 'Choose an organization';

  @override
  String get organizationEmptyTitle => 'No organization yet';

  @override
  String get organizationEmptyBody =>
      'Create an organization or open an invitation link to get started.';

  @override
  String get organizationNameLabel => 'Organization name';

  @override
  String get createOrganization => 'Create organization';

  @override
  String get creatingOrganization => 'Creating organization…';

  @override
  String get organizationLoadFailed => 'We couldn’t load your organizations.';

  @override
  String get organizationCreateFailed =>
      'We couldn’t create the organization. Try again.';

  @override
  String get farmEmptyTitle => 'No farms yet';

  @override
  String get farmEmptyBody =>
      'Your organization is ready. Add a farm to start managing its work.';

  @override
  String get organizationStatusActive => 'Active';

  @override
  String get organizationStatusSuspended => 'Unavailable';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleAdmin => 'Administrator';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleWorker => 'Worker';

  @override
  String get roleViewer => 'Viewer';

  @override
  String get signOutTitle => 'Sign out?';

  @override
  String get signOutBody =>
      'Your saved offline work stays protected on this device.';

  @override
  String get signOut => 'Sign out';

  @override
  String get organizationChanged =>
      'Organization changed. Refreshing the view.';

  @override
  String get changeOrganization => 'Change organization';

  @override
  String get changeFarm => 'Change farm';

  @override
  String farmCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# farms',
      one: '# farm',
      zero: 'No farms',
    );
    return '$_temp0';
  }

  @override
  String get organizationNameRequired => 'Enter an organization name.';

  @override
  String get farmDirectoryLoadFailed =>
      'We couldn’t load this organization’s farm access.';

  @override
  String get inviteInvalidTitle => 'Invitation link unavailable';

  @override
  String get inviteInvalidBody =>
      'Check the invitation link or ask an organization owner for a new one.';

  @override
  String get inviteAccept => 'Accept invitation';

  @override
  String get inviteAccepting => 'Accepting invitation…';

  @override
  String get inviteExpired =>
      'This invitation has expired. Ask an owner or administrator for a new one.';

  @override
  String get inviteRevoked =>
      'This invitation was withdrawn. Ask an owner or administrator for a new one.';

  @override
  String get inviteUnavailable =>
      'This invitation is unavailable. Ask an organization owner for help.';

  @override
  String get inviteEmailMismatch =>
      'Sign in with the email address that received this invitation.';

  @override
  String get inviteAlreadyAccepted =>
      'This invitation has already been accepted.';

  @override
  String get inviteAcceptFailed =>
      'We couldn’t accept this invitation. Try again.';

  @override
  String get inviteAccepted =>
      'Invitation accepted. Your organization is ready.';

  @override
  String get profileSyncCenter => 'Sync Center';

  @override
  String profileAiConsentAccepted(int revision) {
    return 'Farm data is included in contextual chats (consent revision $revision).';
  }

  @override
  String get profileAiConsentGeneral =>
      'General mode is active; private farm data is not attached.';

  @override
  String get profileAiConsentUnselected =>
      'You have not chosen a conversation mode.';

  @override
  String profileAiUsageKnown(int inputTokens, int outputTokens) {
    return 'This month: $inputTokens input tokens and $outputTokens output tokens (illustrative demo figures).';
  }

  @override
  String get profileAiUsageUnavailable =>
      'Monthly usage is unavailable; the server has not returned figures.';

  @override
  String get profilePrivacyTitle => 'Data privacy';

  @override
  String get privacyExportTitle => 'Export my data';

  @override
  String get privacyExportSubtitle =>
      'Download your account and farm data package.';

  @override
  String get privacyExportDone => 'Export package ready.';

  @override
  String get privacyExportViewAction => 'View data';

  @override
  String get privacyCopyAction => 'Copy';

  @override
  String get privacyCopied => 'Copied to clipboard.';

  @override
  String get privacyDeleteHistoryTitle => 'Delete AI chat history';

  @override
  String get privacyDeleteHistorySubtitle =>
      'Conversation content is permanently deleted; the server keeps content-free proof records.';

  @override
  String get privacyDeleteHistoryConfirm =>
      'Delete all of your AI conversation content? This cannot be undone.';

  @override
  String privacyDeleteHistoryDone(int count) {
    return 'Deleted content of $count conversations.';
  }

  @override
  String get privacyWithdrawAiTitle => 'Withdraw Farmly AI consent';

  @override
  String get privacyWithdrawAiSubtitle =>
      'Farmly AI stops using your farm data in conversations until you consent again.';

  @override
  String get privacyWithdrawAiConfirm =>
      'Withdrawing consent cancels every running AI request. Continue?';

  @override
  String get privacyWithdrawAiDone => 'Farmly AI consent withdrawn.';

  @override
  String get privacyRequestFailed =>
      'Could not complete the request. Try again.';

  @override
  String get profileLanguageTitle => 'Language';

  @override
  String get profileLanguageSubtitle =>
      'Vietnamese is the current default in this demo.';

  @override
  String get profileAccessibilityTitle => 'Text size and motion';

  @override
  String get profileAccessibilitySubtitle =>
      'Follows system settings; the app does not shrink text to fit.';

  @override
  String syncPendingShort(int count) {
    return '$count waiting';
  }

  @override
  String syncPendingDescription(int count) {
    return '$count items waiting to sync';
  }

  @override
  String syncConflictShort(int count) {
    return '$count conflicts';
  }

  @override
  String syncConflictDescription(int count) {
    return '$count conflicting items';
  }

  @override
  String syncStatusDescription(String details) {
    return 'Sync status: $details. Open Sync Center.';
  }
}
