import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Farmly'**
  String get appName;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your farm, thoughtfully managed'**
  String get appSubtitle;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name}'**
  String greetingMorning(String name);

  /// No description provided for @greetingNoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, {name}'**
  String greetingNoon(String name);

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon, {name}'**
  String greetingAfternoon(String name);

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening, {name}'**
  String greetingEvening(String name);

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @homeTab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTab;

  /// No description provided for @farmTab.
  ///
  /// In en, this message translates to:
  /// **'My Farm'**
  String get farmTab;

  /// No description provided for @analyticsTab.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get analyticsTab;

  /// No description provided for @harvestTab.
  ///
  /// In en, this message translates to:
  /// **'Harvest'**
  String get harvestTab;

  /// No description provided for @profileTab.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTab;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get confirm;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Farmly'**
  String get loginTitle;

  /// No description provided for @loginDescription.
  ///
  /// In en, this message translates to:
  /// **'Welcome back to your farm.'**
  String get loginDescription;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @fullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullNameLabel;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// No description provided for @keepSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Keep me signed in on this device'**
  String get keepSignedIn;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @createAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'New to Farmly? Create an account'**
  String get createAccountPrompt;

  /// No description provided for @haveAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get haveAccountPrompt;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address.'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get emailInvalid;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your name.'**
  String get nameRequired;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get passwordRequired;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters.'**
  String get passwordTooShort;

  /// No description provided for @passwordTooLong.
  ///
  /// In en, this message translates to:
  /// **'Use no more than 128 characters.'**
  String get passwordTooLong;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match.'**
  String get passwordsDoNotMatch;

  /// No description provided for @invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect. Check them and try again.'**
  String get invalidCredentials;

  /// No description provided for @emailNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Verify your email before signing in. Check your inbox for the link.'**
  String get emailNotVerified;

  /// No description provided for @rateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a little, then try again.'**
  String get rateLimited;

  /// No description provided for @authUnavailable.
  ///
  /// In en, this message translates to:
  /// **'We can’t reach Farmly right now. Check your connection and try again.'**
  String get authUnavailable;

  /// No description provided for @authUnexpected.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t complete that request. Try again.'**
  String get authUnexpected;

  /// No description provided for @signOutUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'You are signed out on this device, but Farmly could not confirm server sign-out.'**
  String get signOutUnconfirmed;

  /// No description provided for @createAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createAccountTitle;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @creatingAccount.
  ///
  /// In en, this message translates to:
  /// **'Creating account…'**
  String get creatingAccount;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailBody.
  ///
  /// In en, this message translates to:
  /// **'If this address can be registered, Farmly sent a verification link. Open it, then return here to sign in.'**
  String get verifyEmailBody;

  /// No description provided for @resendVerification.
  ///
  /// In en, this message translates to:
  /// **'Send the verification link again'**
  String get resendVerification;

  /// No description provided for @verificationSent.
  ///
  /// In en, this message translates to:
  /// **'If the address is eligible, a new link is on its way.'**
  String get verificationSent;

  /// No description provided for @verifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get verifiedTitle;

  /// No description provided for @verifiedBody.
  ///
  /// In en, this message translates to:
  /// **'Your email is ready. Sign in to continue.'**
  String get verifiedBody;

  /// No description provided for @invalidLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'This link can’t be used'**
  String get invalidLinkTitle;

  /// No description provided for @invalidLinkBody.
  ///
  /// In en, this message translates to:
  /// **'It may have expired or already been used. Request a new link and try again.'**
  String get invalidLinkBody;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Enter your email. If an account can be found, we’ll send a reset link.'**
  String get forgotPasswordBody;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get sendResetLink;

  /// No description provided for @resetRequested.
  ///
  /// In en, this message translates to:
  /// **'If an account can be found, a reset link is on its way.'**
  String get resetRequested;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get resetPasswordTitle;

  /// No description provided for @saveNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Save new password'**
  String get saveNewPassword;

  /// No description provided for @passwordResetComplete.
  ///
  /// In en, this message translates to:
  /// **'Your password has been changed. Sign in with the new password.'**
  String get passwordResetComplete;

  /// No description provided for @sessionUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Can’t verify your session'**
  String get sessionUnavailableTitle;

  /// No description provided for @sessionUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to check your session, or sign in again.'**
  String get sessionUnavailableBody;

  /// No description provided for @offlineLeaseExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'Your offline access period has ended. Connect to the internet and sign in to continue. Saved work stays protected on this device.'**
  String get offlineLeaseExpiredBody;

  /// No description provided for @resetLinkInstructions.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password for your Farmly account.'**
  String get resetLinkInstructions;

  /// No description provided for @changeScope.
  ///
  /// In en, this message translates to:
  /// **'Change scope'**
  String get changeScope;

  /// No description provided for @farmPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a farm'**
  String get farmPickerTitle;

  /// No description provided for @organizationPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an organization'**
  String get organizationPickerTitle;

  /// No description provided for @farmPickerOrganizationHint.
  ///
  /// In en, this message translates to:
  /// **'To change organization, open Profile → Organizations.'**
  String get farmPickerOrganizationHint;

  /// No description provided for @farmRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'Farm {farm}, organization {organization}'**
  String farmRowSemantics(String farm, String organization);

  /// No description provided for @farmIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Farm ID: {farmId}'**
  String farmIdentifier(String farmId);

  /// No description provided for @farmScopeSummary.
  ///
  /// In en, this message translates to:
  /// **'{organization} · {farm}'**
  String farmScopeSummary(String organization, String farm);

  /// No description provided for @sampleDataNotice.
  ///
  /// In en, this message translates to:
  /// **'Preview data only. These figures are examples, not live farm records.'**
  String get sampleDataNotice;

  /// No description provided for @sampleDataLabel.
  ///
  /// In en, this message translates to:
  /// **'Sample data'**
  String get sampleDataLabel;

  /// No description provided for @noSelectedFarm.
  ///
  /// In en, this message translates to:
  /// **'No farm selected'**
  String get noSelectedFarm;

  /// No description provided for @permissionBannerSemantics.
  ///
  /// In en, this message translates to:
  /// **'Permission notice: {message}'**
  String permissionBannerSemantics(String message);

  /// No description provided for @organizationRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'Organization {name}'**
  String organizationRowSemantics(String name);

  /// No description provided for @openNotifications.
  ///
  /// In en, this message translates to:
  /// **'Open notifications'**
  String get openNotifications;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get notificationsEmpty;

  /// No description provided for @notificationUnreadSemantics.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get notificationUnreadSemantics;

  /// No description provided for @notificationReadSemantics.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get notificationReadSemantics;

  /// No description provided for @notificationPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off. Enable them in system settings to receive alerts outside Farmly.'**
  String get notificationPermissionMessage;

  /// No description provided for @notificationPermissionAction.
  ///
  /// In en, this message translates to:
  /// **'How to enable'**
  String get notificationPermissionAction;

  /// No description provided for @notificationGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on Farmly notifications'**
  String get notificationGuideTitle;

  /// No description provided for @notificationGuideBody.
  ///
  /// In en, this message translates to:
  /// **'1. Open your phone’s Settings app.\n2. Choose Apps → Farmly.\n3. Open Notifications and turn on Allow notifications.\n4. Return to Farmly to receive alerts outside the app.'**
  String get notificationGuideBody;

  /// No description provided for @understood.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get understood;

  /// No description provided for @loadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load data'**
  String get loadErrorTitle;

  /// No description provided for @loadErrorBody.
  ///
  /// In en, this message translates to:
  /// **'There was a problem loading this data. It has not been saved to this device. Try again or change the scope.'**
  String get loadErrorBody;

  /// No description provided for @permissionDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'You don’t have permission to view this'**
  String get permissionDeniedTitle;

  /// No description provided for @offlineNoDate.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing data saved on this device.'**
  String get offlineNoDate;

  /// No description provided for @offlineWithDate.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing the device copy (data through {asOf}).'**
  String offlineWithDate(String asOf);

  /// No description provided for @offlineSemantics.
  ///
  /// In en, this message translates to:
  /// **'No connection, showing saved data through {asOf}.'**
  String offlineSemantics(String asOf);

  /// No description provided for @offlineSemanticsNoDate.
  ///
  /// In en, this message translates to:
  /// **'No connection, showing saved data.'**
  String get offlineSemanticsNoDate;

  /// No description provided for @conflictBannerSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count} items need conflict resolution. Open Sync Center.'**
  String conflictBannerSemantics(int count);

  /// No description provided for @conflictBannerBody.
  ///
  /// In en, this message translates to:
  /// **'{count} conflicting records need your attention.'**
  String conflictBannerBody(int count);

  /// No description provided for @demoState.
  ///
  /// In en, this message translates to:
  /// **'Demo state'**
  String get demoState;

  /// No description provided for @demoStateCurrent.
  ///
  /// In en, this message translates to:
  /// **'Demo state: {state}'**
  String demoStateCurrent(String state);

  /// No description provided for @demoStateSwitchSemantics.
  ///
  /// In en, this message translates to:
  /// **'Change this screen’s demo state'**
  String get demoStateSwitchSemantics;

  /// No description provided for @demoStateSelected.
  ///
  /// In en, this message translates to:
  /// **'Switch screen to {state}{selected}'**
  String demoStateSelected(String state, String selected);

  /// No description provided for @demoSelectedSuffix.
  ///
  /// In en, this message translates to:
  /// **', selected'**
  String get demoSelectedSuffix;

  /// No description provided for @demoSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get demoSuccess;

  /// No description provided for @demoLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get demoLoading;

  /// No description provided for @demoEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get demoEmpty;

  /// No description provided for @demoRecoverableError.
  ///
  /// In en, this message translates to:
  /// **'Recoverable error'**
  String get demoRecoverableError;

  /// No description provided for @demoOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get demoOffline;

  /// No description provided for @demoPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get demoPermissionDenied;

  /// No description provided for @demoPendingConflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict pending'**
  String get demoPendingConflict;

  /// No description provided for @homePermissionDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Your account can’t view this farm. Change scope or contact the farm owner.'**
  String get homePermissionDeniedBody;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your farm is ready to grow'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add your first growing zone or livestock area to track work and production.'**
  String get homeEmptyBody;

  /// No description provided for @switchFarm.
  ///
  /// In en, this message translates to:
  /// **'Change farm'**
  String get switchFarm;

  /// No description provided for @weatherSunny.
  ///
  /// In en, this message translates to:
  /// **'Sunny'**
  String get weatherSunny;

  /// No description provided for @windLight.
  ///
  /// In en, this message translates to:
  /// **'Light wind'**
  String get windLight;

  /// No description provided for @weatherHumidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity {humidity}%'**
  String weatherHumidity(int humidity);

  /// No description provided for @quickStats.
  ///
  /// In en, this message translates to:
  /// **'Quick stats'**
  String get quickStats;

  /// No description provided for @weatherSemantics.
  ///
  /// In en, this message translates to:
  /// **'{condition}, {temperature} degrees C, humidity {humidity}%, {wind}; {source} {asOf}.'**
  String weatherSemantics(
    String condition,
    int temperature,
    int humidity,
    String wind,
    String source,
    String asOf,
  );

  /// No description provided for @todayForecastSource.
  ///
  /// In en, this message translates to:
  /// **'today’s forecast'**
  String get todayForecastSource;

  /// No description provided for @savedDataSource.
  ///
  /// In en, this message translates to:
  /// **'saved data'**
  String get savedDataSource;

  /// No description provided for @asOfSource.
  ///
  /// In en, this message translates to:
  /// **'Data through {asOf} · source {source}'**
  String asOfSource(String asOf, String source);

  /// No description provided for @operationalHealth.
  ///
  /// In en, this message translates to:
  /// **'Operations health'**
  String get operationalHealth;

  /// No description provided for @operationalHealthEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated from today’s feeding progress.'**
  String get operationalHealthEstimate;

  /// No description provided for @operationalHealthUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not enough data today to estimate operations health.'**
  String get operationalHealthUnknown;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @todayTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks today'**
  String get todayTasks;

  /// No description provided for @tasksDoneSemantics.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} tasks'**
  String tasksDoneSemantics(int done, int total);

  /// No description provided for @livestock.
  ///
  /// In en, this message translates to:
  /// **'Livestock'**
  String get livestock;

  /// No description provided for @animalUnit.
  ///
  /// In en, this message translates to:
  /// **'animals'**
  String get animalUnit;

  /// No description provided for @zones.
  ///
  /// In en, this message translates to:
  /// **'Zones'**
  String get zones;

  /// No description provided for @zoneUnit.
  ///
  /// In en, this message translates to:
  /// **'zones'**
  String get zoneUnit;

  /// No description provided for @currentHarvest.
  ///
  /// In en, this message translates to:
  /// **'Harvest this period'**
  String get currentHarvest;

  /// No description provided for @harvestValueSemantics.
  ///
  /// In en, this message translates to:
  /// **'{amount} kilograms'**
  String harvestValueSemantics(String amount);

  /// No description provided for @pendingHarvestAmount.
  ///
  /// In en, this message translates to:
  /// **', plus {amount} kilograms waiting to sync'**
  String pendingHarvestAmount(String amount);

  /// No description provided for @askFarmlyAi.
  ///
  /// In en, this message translates to:
  /// **'Ask Farmly AI'**
  String get askFarmlyAi;

  /// No description provided for @askFarmlyAiSemantics.
  ///
  /// In en, this message translates to:
  /// **'Ask Farmly AI. Open the read-only farm assistant.'**
  String get askFarmlyAiSemantics;

  /// No description provided for @organizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an organization'**
  String get organizationTitle;

  /// No description provided for @organizationEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No organization yet'**
  String get organizationEmptyTitle;

  /// No description provided for @organizationEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Create an organization or open an invitation link to get started.'**
  String get organizationEmptyBody;

  /// No description provided for @organizationNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Organization name'**
  String get organizationNameLabel;

  /// No description provided for @createOrganization.
  ///
  /// In en, this message translates to:
  /// **'Create organization'**
  String get createOrganization;

  /// No description provided for @creatingOrganization.
  ///
  /// In en, this message translates to:
  /// **'Creating organization…'**
  String get creatingOrganization;

  /// No description provided for @organizationLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t load your organizations.'**
  String get organizationLoadFailed;

  /// No description provided for @organizationCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t create the organization. Try again.'**
  String get organizationCreateFailed;

  /// No description provided for @farmEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No farms yet'**
  String get farmEmptyTitle;

  /// No description provided for @farmEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Your organization is ready. Add a farm to start managing its work.'**
  String get farmEmptyBody;

  /// No description provided for @organizationStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get organizationStatusActive;

  /// No description provided for @organizationStatusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get organizationStatusSuspended;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get roleAdmin;

  /// No description provided for @roleManager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get roleManager;

  /// No description provided for @roleWorker.
  ///
  /// In en, this message translates to:
  /// **'Worker'**
  String get roleWorker;

  /// No description provided for @roleViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get roleViewer;

  /// No description provided for @signOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOutTitle;

  /// No description provided for @signOutBody.
  ///
  /// In en, this message translates to:
  /// **'Your saved offline work stays protected on this device.'**
  String get signOutBody;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @organizationChanged.
  ///
  /// In en, this message translates to:
  /// **'Organization changed. Refreshing the view.'**
  String get organizationChanged;

  /// No description provided for @changeOrganization.
  ///
  /// In en, this message translates to:
  /// **'Change organization'**
  String get changeOrganization;

  /// No description provided for @changeFarm.
  ///
  /// In en, this message translates to:
  /// **'Change farm'**
  String get changeFarm;

  /// No description provided for @farmCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No farms} one{# farm} other{# farms}}'**
  String farmCount(int count);

  /// No description provided for @organizationNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an organization name.'**
  String get organizationNameRequired;

  /// No description provided for @farmDirectoryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t load this organization’s farm access.'**
  String get farmDirectoryLoadFailed;

  /// No description provided for @inviteInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'Invitation link unavailable'**
  String get inviteInvalidTitle;

  /// No description provided for @inviteInvalidBody.
  ///
  /// In en, this message translates to:
  /// **'Check the invitation link or ask an organization owner for a new one.'**
  String get inviteInvalidBody;

  /// No description provided for @inviteAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept invitation'**
  String get inviteAccept;

  /// No description provided for @inviteAccepting.
  ///
  /// In en, this message translates to:
  /// **'Accepting invitation…'**
  String get inviteAccepting;

  /// No description provided for @inviteExpired.
  ///
  /// In en, this message translates to:
  /// **'This invitation has expired. Ask an owner or administrator for a new one.'**
  String get inviteExpired;

  /// No description provided for @inviteRevoked.
  ///
  /// In en, this message translates to:
  /// **'This invitation was withdrawn. Ask an owner or administrator for a new one.'**
  String get inviteRevoked;

  /// No description provided for @inviteUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This invitation is unavailable. Ask an organization owner for help.'**
  String get inviteUnavailable;

  /// No description provided for @inviteEmailMismatch.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the email address that received this invitation.'**
  String get inviteEmailMismatch;

  /// No description provided for @inviteAlreadyAccepted.
  ///
  /// In en, this message translates to:
  /// **'This invitation has already been accepted.'**
  String get inviteAlreadyAccepted;

  /// No description provided for @inviteAcceptFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t accept this invitation. Try again.'**
  String get inviteAcceptFailed;

  /// No description provided for @inviteAccepted.
  ///
  /// In en, this message translates to:
  /// **'Invitation accepted. Your organization is ready.'**
  String get inviteAccepted;

  /// No description provided for @profileSyncCenter.
  ///
  /// In en, this message translates to:
  /// **'Sync Center'**
  String get profileSyncCenter;

  /// No description provided for @profileAiConsentAccepted.
  ///
  /// In en, this message translates to:
  /// **'Farm data is included in contextual chats (consent revision {revision}).'**
  String profileAiConsentAccepted(int revision);

  /// No description provided for @profileAiConsentGeneral.
  ///
  /// In en, this message translates to:
  /// **'General mode is active; private farm data is not attached.'**
  String get profileAiConsentGeneral;

  /// No description provided for @profileAiConsentUnselected.
  ///
  /// In en, this message translates to:
  /// **'You have not chosen a conversation mode.'**
  String get profileAiConsentUnselected;

  /// No description provided for @profileAiUsageKnown.
  ///
  /// In en, this message translates to:
  /// **'This month: {inputTokens} input tokens and {outputTokens} output tokens (illustrative demo figures).'**
  String profileAiUsageKnown(int inputTokens, int outputTokens);

  /// No description provided for @profileAiUsageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Monthly usage is unavailable; the server has not returned figures.'**
  String get profileAiUsageUnavailable;

  /// No description provided for @profilePrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Data privacy'**
  String get profilePrivacyTitle;

  /// No description provided for @privacyExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get privacyExportTitle;

  /// No description provided for @privacyExportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download your account and farm data package.'**
  String get privacyExportSubtitle;

  /// No description provided for @privacyExportDone.
  ///
  /// In en, this message translates to:
  /// **'Export package ready.'**
  String get privacyExportDone;

  /// No description provided for @privacyExportViewAction.
  ///
  /// In en, this message translates to:
  /// **'View data'**
  String get privacyExportViewAction;

  /// No description provided for @privacyCopyAction.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get privacyCopyAction;

  /// No description provided for @privacyCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard.'**
  String get privacyCopied;

  /// No description provided for @privacyDeleteHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete AI chat history'**
  String get privacyDeleteHistoryTitle;

  /// No description provided for @privacyDeleteHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation content is permanently deleted; the server keeps content-free proof records.'**
  String get privacyDeleteHistorySubtitle;

  /// No description provided for @privacyDeleteHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete all of your AI conversation content? This cannot be undone.'**
  String get privacyDeleteHistoryConfirm;

  /// No description provided for @privacyDeleteHistoryDone.
  ///
  /// In en, this message translates to:
  /// **'Deleted content of {count} conversations.'**
  String privacyDeleteHistoryDone(int count);

  /// No description provided for @privacyWithdrawAiTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdraw Farmly AI consent'**
  String get privacyWithdrawAiTitle;

  /// No description provided for @privacyWithdrawAiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Farmly AI stops using your farm data in conversations until you consent again.'**
  String get privacyWithdrawAiSubtitle;

  /// No description provided for @privacyWithdrawAiConfirm.
  ///
  /// In en, this message translates to:
  /// **'Withdrawing consent cancels every running AI request. Continue?'**
  String get privacyWithdrawAiConfirm;

  /// No description provided for @privacyWithdrawAiDone.
  ///
  /// In en, this message translates to:
  /// **'Farmly AI consent withdrawn.'**
  String get privacyWithdrawAiDone;

  /// No description provided for @privacyRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the request. Try again.'**
  String get privacyRequestFailed;

  /// No description provided for @profileLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get profileLanguageTitle;

  /// No description provided for @profileLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vietnamese is the current default in this demo.'**
  String get profileLanguageSubtitle;

  /// No description provided for @profileAccessibilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Text size and motion'**
  String get profileAccessibilityTitle;

  /// No description provided for @profileAccessibilitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follows system settings; the app does not shrink text to fit.'**
  String get profileAccessibilitySubtitle;

  /// No description provided for @syncPendingShort.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting'**
  String syncPendingShort(int count);

  /// No description provided for @syncPendingDescription.
  ///
  /// In en, this message translates to:
  /// **'{count} items waiting to sync'**
  String syncPendingDescription(int count);

  /// No description provided for @syncConflictShort.
  ///
  /// In en, this message translates to:
  /// **'{count} conflicts'**
  String syncConflictShort(int count);

  /// No description provided for @syncConflictDescription.
  ///
  /// In en, this message translates to:
  /// **'{count} conflicting items'**
  String syncConflictDescription(int count);

  /// No description provided for @syncStatusDescription.
  ///
  /// In en, this message translates to:
  /// **'Sync status: {details}. Open Sync Center.'**
  String syncStatusDescription(String details);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
