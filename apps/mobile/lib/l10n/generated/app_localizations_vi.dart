// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appName => 'Farmly';

  @override
  String get appSubtitle => 'Quản lý trang trại chu đáo hơn';

  @override
  String greetingMorning(String name) {
    return 'Chào buổi sáng, $name';
  }

  @override
  String greetingNoon(String name) {
    return 'Chào buổi trưa, $name';
  }

  @override
  String greetingAfternoon(String name) {
    return 'Chào buổi chiều, $name';
  }

  @override
  String greetingEvening(String name) {
    return 'Chào buổi tối, $name';
  }

  @override
  String get loading => 'Đang tải';

  @override
  String get homeTab => 'Trang chủ';

  @override
  String get farmTab => 'Nông trại';

  @override
  String get analyticsTab => 'Phân tích';

  @override
  String get harvestTab => 'Thu hoạch';

  @override
  String get profileTab => 'Cá nhân';

  @override
  String get back => 'Quay lại';

  @override
  String get retry => 'Thử lại';

  @override
  String get continueLabel => 'Tiếp tục';

  @override
  String get cancel => 'Hủy';

  @override
  String get confirm => 'Tiếp tục';

  @override
  String get loginTitle => 'Đăng nhập Farmly';

  @override
  String get loginDescription => 'Chào mừng bạn trở lại với trang trại.';

  @override
  String get emailLabel => 'Địa chỉ email';

  @override
  String get passwordLabel => 'Mật khẩu';

  @override
  String get fullNameLabel => 'Họ và tên';

  @override
  String get confirmPasswordLabel => 'Nhập lại mật khẩu';

  @override
  String get keepSignedIn => 'Duy trì đăng nhập trên thiết bị này';

  @override
  String get signIn => 'Đăng nhập';

  @override
  String get signingIn => 'Đang đăng nhập…';

  @override
  String get forgotPassword => 'Quên mật khẩu?';

  @override
  String get createAccountPrompt => 'Chưa có tài khoản? Tạo tài khoản';

  @override
  String get haveAccountPrompt => 'Đã có tài khoản? Đăng nhập';

  @override
  String get showPassword => 'Hiện mật khẩu';

  @override
  String get hidePassword => 'Ẩn mật khẩu';

  @override
  String get emailRequired => 'Nhập địa chỉ email.';

  @override
  String get emailInvalid => 'Nhập địa chỉ email hợp lệ.';

  @override
  String get nameRequired => 'Nhập họ và tên.';

  @override
  String get passwordRequired => 'Nhập mật khẩu.';

  @override
  String get passwordTooShort => 'Mật khẩu cần ít nhất 8 ký tự.';

  @override
  String get passwordTooLong => 'Mật khẩu không được dài quá 128 ký tự.';

  @override
  String get passwordsDoNotMatch => 'Hai mật khẩu không khớp.';

  @override
  String get invalidCredentials =>
      'Email hoặc mật khẩu chưa đúng. Hãy kiểm tra và thử lại.';

  @override
  String get emailNotVerified =>
      'Hãy xác minh email trước khi đăng nhập. Kiểm tra hộp thư để tìm liên kết.';

  @override
  String get rateLimited =>
      'Bạn đã thử quá nhiều lần. Hãy đợi một chút rồi thử lại.';

  @override
  String get authUnavailable =>
      'Chưa thể kết nối tới Farmly. Hãy kiểm tra mạng rồi thử lại.';

  @override
  String get authUnexpected => 'Chưa thể hoàn tất yêu cầu. Hãy thử lại.';

  @override
  String get signOutUnconfirmed =>
      'Thiết bị đã đăng xuất, nhưng Farmly chưa xác nhận được việc kết thúc phiên trên máy chủ.';

  @override
  String get createAccountTitle => 'Tạo tài khoản';

  @override
  String get createAccount => 'Tạo tài khoản';

  @override
  String get creatingAccount => 'Đang tạo tài khoản…';

  @override
  String get verifyEmailTitle => 'Kiểm tra email';

  @override
  String get verifyEmailBody =>
      'Nếu địa chỉ này đăng ký được, Farmly đã gửi liên kết xác minh. Hãy mở liên kết rồi quay lại đăng nhập.';

  @override
  String get resendVerification => 'Gửi lại liên kết xác minh';

  @override
  String get verificationSent =>
      'Nếu địa chỉ đủ điều kiện, liên kết mới sẽ được gửi tới hộp thư.';

  @override
  String get verifiedTitle => 'Email đã được xác minh';

  @override
  String get verifiedBody =>
      'Email của bạn đã sẵn sàng. Hãy đăng nhập để tiếp tục.';

  @override
  String get invalidLinkTitle => 'Không thể dùng liên kết này';

  @override
  String get invalidLinkBody =>
      'Liên kết có thể đã hết hạn hoặc được sử dụng. Hãy yêu cầu liên kết mới.';

  @override
  String get forgotPasswordTitle => 'Đặt lại mật khẩu';

  @override
  String get forgotPasswordBody =>
      'Nhập email. Nếu tìm thấy tài khoản, chúng tôi sẽ gửi liên kết đặt lại.';

  @override
  String get sendResetLink => 'Gửi liên kết đặt lại';

  @override
  String get resetRequested =>
      'Nếu tìm thấy tài khoản, liên kết đặt lại sẽ được gửi tới hộp thư.';

  @override
  String get resetPasswordTitle => 'Chọn mật khẩu mới';

  @override
  String get saveNewPassword => 'Lưu mật khẩu mới';

  @override
  String get passwordResetComplete =>
      'Mật khẩu đã đổi. Hãy đăng nhập bằng mật khẩu mới.';

  @override
  String get sessionUnavailableTitle => 'Chưa thể xác minh phiên';

  @override
  String get sessionUnavailableBody =>
      'Kết nối Internet để kiểm tra phiên, hoặc đăng nhập lại.';

  @override
  String get offlineLeaseExpiredBody =>
      'Thời hạn truy cập ngoại tuyến đã kết thúc. Hãy kết nối Internet và đăng nhập để tiếp tục. Công việc đã lưu vẫn được bảo vệ trên thiết bị.';

  @override
  String get resetLinkInstructions =>
      'Chọn mật khẩu mới cho tài khoản Farmly của bạn.';

  @override
  String get changeScope => 'Đổi phạm vi';

  @override
  String get farmPickerTitle => 'Chọn nông trại';

  @override
  String get organizationPickerTitle => 'Chọn tổ chức';

  @override
  String get farmPickerOrganizationHint =>
      'Để đổi tổ chức, mở Cá nhân → Tổ chức.';

  @override
  String farmRowSemantics(String farm, String organization) {
    return 'Nông trại $farm, tổ chức $organization';
  }

  @override
  String farmIdentifier(String farmId) {
    return 'Mã nông trại: $farmId';
  }

  @override
  String farmScopeSummary(String organization, String farm) {
    return '$organization · $farm';
  }

  @override
  String get sampleDataNotice =>
      'Dữ liệu xem trước. Các số liệu này chỉ là ví dụ, không phải hồ sơ trực tiếp của nông trại.';

  @override
  String get sampleDataLabel => 'Dữ liệu mẫu';

  @override
  String get noSelectedFarm => 'Chưa chọn nông trại';

  @override
  String permissionBannerSemantics(String message) {
    return 'Thông báo quyền: $message';
  }

  @override
  String organizationRowSemantics(String name) {
    return 'Tổ chức $name';
  }

  @override
  String get openNotifications => 'Mở thông báo';

  @override
  String get notificationsTitle => 'Thông báo';

  @override
  String get notificationsEmpty => 'Chưa có thông báo nào.';

  @override
  String get notificationUnreadSemantics => 'Chưa đọc';

  @override
  String get notificationReadSemantics => 'Đã đọc';

  @override
  String get notificationPermissionMessage =>
      'Thông báo đang bị tắt. Hãy bật trong cài đặt hệ thống để nhận cảnh báo ngoài Farmly.';

  @override
  String get notificationPermissionAction => 'Cách bật thông báo';

  @override
  String get notificationGuideTitle => 'Bật thông báo cho Farmly';

  @override
  String get notificationGuideBody =>
      '1. Mở ứng dụng Cài đặt của điện thoại.\n2. Chọn Ứng dụng → Farmly.\n3. Mở mục Thông báo và bật Cho phép thông báo.\n4. Quay lại Farmly để nhận cảnh báo ngoài ứng dụng.';

  @override
  String get understood => 'Đã hiểu';

  @override
  String get loadErrorTitle => 'Không tải được dữ liệu';

  @override
  String get loadErrorBody =>
      'Đã có lỗi khi tải. Dữ liệu chưa được lưu trên thiết bị — bạn có thể thử lại hoặc đổi phạm vi xem.';

  @override
  String get permissionDeniedTitle => 'Bạn không có quyền xem mục này';

  @override
  String get offlineNoDate =>
      'Ngoại tuyến — đang hiển thị dữ liệu đã lưu trên thiết bị.';

  @override
  String offlineWithDate(String asOf) {
    return 'Ngoại tuyến — đang hiển thị bản lưu trên thiết bị (dữ liệu đến $asOf).';
  }

  @override
  String offlineSemantics(String asOf) {
    return 'Không có kết nối, đang hiển thị dữ liệu đã lưu đến $asOf.';
  }

  @override
  String get offlineSemanticsNoDate =>
      'Không có kết nối, đang hiển thị dữ liệu đã lưu.';

  @override
  String conflictBannerSemantics(int count) {
    return 'Có $count mục cần xử lý xung đột. Mở trung tâm đồng bộ.';
  }

  @override
  String conflictBannerBody(int count) {
    return 'Có $count bản ghi xung đột cần bạn xử lý.';
  }

  @override
  String get demoState => 'Trạng thái demo';

  @override
  String demoStateCurrent(String state) {
    return 'Trạng thái demo: $state';
  }

  @override
  String get demoStateSwitchSemantics =>
      'Chuyển trạng thái demo của màn hình này';

  @override
  String demoStateSelected(String state, String selected) {
    return 'Chuyển màn sang trạng thái $state$selected';
  }

  @override
  String get demoSelectedSuffix => ', đang chọn';

  @override
  String get demoSuccess => 'Thành công';

  @override
  String get demoLoading => 'Đang tải';

  @override
  String get demoEmpty => 'Trống';

  @override
  String get demoRecoverableError => 'Lỗi có thể thử lại';

  @override
  String get demoOffline => 'Ngoại tuyến';

  @override
  String get demoPermissionDenied => 'Không có quyền';

  @override
  String get demoPendingConflict => 'Có xung đột';

  @override
  String get homePermissionDeniedBody =>
      'Tài khoản của bạn không thể xem nông trại này. Hãy đổi phạm vi hoặc liên hệ chủ nông trại.';

  @override
  String get homeEmptyTitle => 'Nông trại của bạn sẵn sàng phát triển';

  @override
  String get homeEmptyBody =>
      'Thêm vùng trồng hoặc khu chăn nuôi đầu tiên để theo dõi công việc và sản lượng.';

  @override
  String get switchFarm => 'Đổi nông trại';

  @override
  String get weatherSunny => 'Trời nắng';

  @override
  String get windLight => 'Gió nhẹ';

  @override
  String weatherHumidity(int humidity) {
    return 'Độ ẩm $humidity%';
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
    return '$condition, $temperature độ C, độ ẩm $humidity%, $wind; $source $asOf.';
  }

  @override
  String get todayForecastSource => 'dự báo hôm nay';

  @override
  String get savedDataSource => 'bản lưu';

  @override
  String asOfSource(String asOf, String source) {
    return 'Dữ liệu đến $asOf · nguồn $source';
  }

  @override
  String get operationalHealth => 'Sức khỏe vận hành';

  @override
  String get operationalHealthEstimate =>
      'Ước lượng từ tiến độ cho ăn hôm nay.';

  @override
  String get operationalHealthUnknown =>
      'Chưa đủ dữ liệu hôm nay để tính sức khỏe vận hành.';

  @override
  String get unknown => 'Chưa rõ';

  @override
  String get todayTasks => 'Nhiệm vụ hôm nay';

  @override
  String tasksDoneSemantics(int done, int total) {
    return 'Đã xong $done trên $total nhiệm vụ';
  }

  @override
  String get livestock => 'Vật nuôi';

  @override
  String get animalUnit => 'con';

  @override
  String get zones => 'Vùng';

  @override
  String get zoneUnit => 'vùng';

  @override
  String get currentHarvest => 'Thu hoạch kỳ này';

  @override
  String harvestValueSemantics(String amount) {
    return '$amount kilô gam';
  }

  @override
  String pendingHarvestAmount(String amount) {
    return ', thêm $amount kilô gam đang chờ đồng bộ';
  }

  @override
  String get askFarmlyAi => 'Hỏi Farmly AI';

  @override
  String get askFarmlyAiSemantics =>
      'Hỏi Farmly AI. Mở trợ lý nông trại chỉ đọc.';

  @override
  String get organizationTitle => 'Chọn tổ chức';

  @override
  String get organizationEmptyTitle => 'Chưa có tổ chức';

  @override
  String get organizationEmptyBody =>
      'Tạo tổ chức hoặc mở liên kết lời mời để bắt đầu.';

  @override
  String get organizationNameLabel => 'Tên tổ chức';

  @override
  String get createOrganization => 'Tạo tổ chức';

  @override
  String get creatingOrganization => 'Đang tạo tổ chức…';

  @override
  String get organizationLoadFailed => 'Chưa thể tải danh sách tổ chức.';

  @override
  String get organizationCreateFailed => 'Chưa thể tạo tổ chức. Hãy thử lại.';

  @override
  String get farmEmptyTitle => 'Chưa có nông trại';

  @override
  String get farmEmptyBody =>
      'Tổ chức đã sẵn sàng. Hãy thêm nông trại để bắt đầu quản lý công việc.';

  @override
  String get organizationStatusActive => 'Đang hoạt động';

  @override
  String get organizationStatusSuspended => 'Không khả dụng';

  @override
  String get roleOwner => 'Chủ sở hữu';

  @override
  String get roleAdmin => 'Quản trị viên';

  @override
  String get roleManager => 'Quản lý';

  @override
  String get roleWorker => 'Nhân viên';

  @override
  String get roleViewer => 'Người xem';

  @override
  String get signOutTitle => 'Đăng xuất?';

  @override
  String get signOutBody =>
      'Công việc ngoại tuyến đã lưu vẫn được bảo vệ trên thiết bị.';

  @override
  String get signOut => 'Đăng xuất';

  @override
  String get organizationChanged => 'Đã đổi tổ chức. Đang làm mới nội dung.';

  @override
  String get changeOrganization => 'Đổi tổ chức';

  @override
  String get changeFarm => 'Đổi nông trại';

  @override
  String farmCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# nông trại',
      zero: 'Chưa có nông trại',
    );
    return '$_temp0';
  }

  @override
  String get organizationNameRequired => 'Nhập tên tổ chức.';

  @override
  String get farmDirectoryLoadFailed =>
      'Chưa thể tải quyền truy cập nông trại của tổ chức này.';

  @override
  String get inviteInvalidTitle => 'Không thể mở lời mời';

  @override
  String get inviteInvalidBody =>
      'Hãy kiểm tra liên kết hoặc xin chủ sở hữu tổ chức gửi lời mời mới.';

  @override
  String get inviteAccept => 'Chấp nhận lời mời';

  @override
  String get inviteAccepting => 'Đang chấp nhận lời mời…';

  @override
  String get inviteExpired =>
      'Lời mời đã hết hạn. Hãy xin chủ sở hữu hoặc quản trị viên gửi lời mời mới.';

  @override
  String get inviteRevoked =>
      'Lời mời đã bị thu hồi. Hãy xin chủ sở hữu hoặc quản trị viên gửi lời mời mới.';

  @override
  String get inviteUnavailable =>
      'Lời mời không khả dụng. Hãy liên hệ chủ sở hữu tổ chức.';

  @override
  String get inviteEmailMismatch =>
      'Hãy đăng nhập bằng email đã nhận lời mời này.';

  @override
  String get inviteAlreadyAccepted => 'Lời mời này đã được chấp nhận.';

  @override
  String get inviteAcceptFailed => 'Chưa thể chấp nhận lời mời. Hãy thử lại.';

  @override
  String get inviteAccepted =>
      'Đã chấp nhận lời mời. Tổ chức của bạn đã sẵn sàng.';

  @override
  String get profileSyncCenter => 'Trung tâm đồng bộ';

  @override
  String profileAiConsentAccepted(int revision) {
    return 'Đã đồng ý dùng dữ liệu trang trại trong hội thoại theo ngữ cảnh (bản đồng thuận số $revision).';
  }

  @override
  String get profileAiConsentGeneral =>
      'Đang ở chế độ chung, không đính kèm dữ liệu riêng.';

  @override
  String get profileAiConsentUnselected => 'Bạn chưa chọn chế độ hội thoại.';

  @override
  String profileAiUsageKnown(int inputTokens, int outputTokens) {
    return 'Tháng này: nhập $inputTokens token, đáp trả $outputTokens token (số liệu minh họa).';
  }

  @override
  String get profileAiUsageUnavailable =>
      'Mức dùng tháng này chưa rõ — máy chủ chưa trả số liệu.';

  @override
  String get profilePrivacyTitle => 'Quyền riêng tư dữ liệu';

  @override
  String get privacyExportTitle => 'Xuất dữ liệu của tôi';

  @override
  String get privacyExportSubtitle =>
      'Tải gói dữ liệu tài khoản và trang trại của bạn.';

  @override
  String get privacyExportDone => 'Gói xuất sẵn sàng.';

  @override
  String get privacyExportViewAction => 'Xem dữ liệu';

  @override
  String get privacyCopyAction => 'Sao chép';

  @override
  String get privacyCopied => 'Đã sao chép vào bộ nhớ tạm.';

  @override
  String get privacyDeleteHistoryTitle => 'Xóa lịch sử hội thoại AI';

  @override
  String get privacyDeleteHistorySubtitle =>
      'Nội dung hội thoại bị xóa vĩnh viễn; máy chủ giữ bản ghi chứng minh không nội dung.';

  @override
  String get privacyDeleteHistoryConfirm =>
      'Xóa toàn bộ nội dung hội thoại AI của bạn? Thao tác này không thể hoàn tác.';

  @override
  String privacyDeleteHistoryDone(int count) {
    return 'Đã xóa nội dung $count cuộc hội thoại.';
  }

  @override
  String get privacyWithdrawAiTitle => 'Rút đồng thuận Farmly AI';

  @override
  String get privacyWithdrawAiSubtitle =>
      'Farmly AI ngừng dùng dữ liệu trang trại trong hội thoại cho tới khi bạn đồng ý lại.';

  @override
  String get privacyWithdrawAiConfirm =>
      'Rút đồng thuận sẽ hủy mọi yêu cầu AI đang chạy. Tiếp tục?';

  @override
  String get privacyWithdrawAiDone => 'Đã rút đồng thuận Farmly AI.';

  @override
  String get privacyRequestFailed => 'Chưa thực hiện được. Hãy thử lại.';

  @override
  String get profileLanguageTitle => 'Ngôn ngữ';

  @override
  String get profileLanguageSubtitle =>
      'Tiếng Việt là ngôn ngữ mặc định hiện tại của bản demo.';

  @override
  String get profileAccessibilityTitle => 'Cỡ chữ và chuyển động';

  @override
  String get profileAccessibilitySubtitle =>
      'Theo cài đặt hệ thống; ứng dụng không tự co chữ để lách.';

  @override
  String syncPendingShort(int count) {
    return '$count chờ';
  }

  @override
  String syncPendingDescription(int count) {
    return '$count mục chờ đồng bộ';
  }

  @override
  String syncConflictShort(int count) {
    return '$count xung đột';
  }

  @override
  String syncConflictDescription(int count) {
    return '$count mục xung đột';
  }

  @override
  String syncStatusDescription(String details) {
    return 'Trạng thái đồng bộ: $details. Mở trung tâm đồng bộ.';
  }
}
