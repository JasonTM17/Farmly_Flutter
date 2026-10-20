import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:farmly_mobile/main_explorer_preview.dart' as preview;
import 'package:farmly_mobile/features/app/app_routes.dart';
import 'package:farmly_mobile/features/auth/auth_flow_screens.dart';
import 'package:farmly_mobile/features/auth/login_screen.dart';
import 'package:farmly_mobile/features/auth/splash_screen.dart';
import 'package:farmly_mobile/features/chat/chat_screens.dart';
import 'package:farmly_mobile/features/farm/farm_overview_screen.dart';
import 'package:farmly_mobile/features/farm/zone_detail_screen.dart';
import 'package:farmly_mobile/features/livestock/livestock_screen.dart';
import 'package:farmly_mobile/features/organizations/organization_flow_screens.dart';
import 'package:farmly_mobile/features/sync/sync_center_screen.dart';
import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';

// Run only against the dedicated Farmly development emulator. The preview
// entrypoint uses local adapters and guards disk sync; this journey submits
// no AI prompts, domain mutations, authentication or organization changes.
// Native screenshots/video are captured independently by the controller via
// adb; named checkpoints in stdout describe the actual rendered choreography.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clay preview real Android navigation and farm zoom journey', (
    tester,
  ) async {
    Future<void> checkpoint(String name) async {
      // Ambient actors intentionally never settle; bounded pumps keep motion
      // enabled and give camera/route transitions time to finish.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull, reason: name);
      debugPrint('FARMLY_NATIVE_SCREEN $name');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
    }

    Future<void> tab(int index) async {
      final targets = find.descendant(
        of: find.byType(AdaptiveBottomBar),
        matching: find.byType(InkWell),
      );
      expect(targets, findsNWidgets(5));
      await tester.tap(targets.at(index));
      await checkpoint('tab-$index');
    }

    Finder farmScroll() => find
        .descendant(
          of: find.byType(FarmOverviewScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> farmTop() async {
      for (var i = 0; i < 3; i++) {
        // Start in the list's left gutter, outside the padded map. A center
        // drag can be consumed by InteractiveViewer as a camera pan.
        await tester.dragFrom(
          tester.getTopLeft(farmScroll()) + const Offset(4, 100),
          const Offset(0, 650),
        );
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> revealFarm(Finder target) async {
      for (var i = 0; i < 30 && target.hitTestable().evaluate().isEmpty; i++) {
        await tester.dragFrom(
          tester.getTopLeft(farmScroll()) + const Offset(4, 220),
          const Offset(0, -180),
        );
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(target.hitTestable(), findsOneWidget);
      await tester.ensureVisible(target);
    }

    Future<void> selectZone(String name, String id) async {
      await farmTop();
      final chip = find.descendant(
        of: find.byType(ZoneChipStrip),
        matching: find.text(name),
      );
      final stripScroll = find.descendant(
        of: find.byType(ZoneChipStrip),
        matching: find.byType(Scrollable),
      );
      // The strip is lazy: distant house/storage chips do not exist yet, so
      // ensureVisible alone cannot locate them. Rewind and scroll real UI.
      for (var i = 0; i < 3; i++) {
        await tester.drag(stripScroll, const Offset(600, 0));
        await tester.pump(const Duration(milliseconds: 150));
      }
      await tester.scrollUntilVisible(
        chip,
        140,
        scrollable: stripScroll,
        maxScrolls: 16,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(chip);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.ancestor(of: chip, matching: find.byType(ChoiceChip)),
      );
      await checkpoint('zoom-$id');
      final scene = tester.widget<ZoneScene>(find.byType(ZoneScene));
      expect(scene.selectedZoneId, id);
      final viewer = tester.widget<InteractiveViewer>(
        find.descendant(
          of: find.byType(ZoneScene),
          matching: find.byType(InteractiveViewer),
        ),
      );
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
    }

    Future<void> detail(String name, String id) async {
      final row = find.descendant(
        of: find.byType(AccessibleZoneList),
        matching: find.text(name),
      );
      await revealFarm(row);
      await tester.tap(row);
      await checkpoint('detail-$id');
      expect(find.byType(ZoneDetailScreen), findsOneWidget);
      expect(
        tester.widget<ZoneDetailScreen>(find.byType(ZoneDetailScreen)).zoneId,
        id,
      );
      await tester.binding.handlePopRoute();
      await checkpoint('back-$id');
    }

    preview.main();
    await checkpoint('farm-boot');
    expect(find.byType(FarmOverviewScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Đổi nông trại').first);
    await checkpoint('farm-picker-sheet');
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await checkpoint('back-farm-picker');

    for (final (name, id) in const [
      ('Rau ăn lá', 'zone-rau-an-la'),
      ('Chuồng gà', 'zone-chuong-ga'),
      ('Bồn nước', 'zone-bon-nuoc'),
      ('Nhà xưởng', 'zone-nha-xuong'),
      ('Kho nông cụ', 'zone-kho'),
    ]) {
      await selectZone(name, id);
      if (id == 'zone-chuong-ga') {
        final livestock = find.text('Mở khu chăn nuôi');
        await revealFarm(livestock);
        await tester.tap(livestock);
        await checkpoint('livestock');
        expect(find.byType(LivestockScreen), findsOneWidget);
        await tester.binding.handlePopRoute();
        await checkpoint('back-livestock');
      }
      await detail(name, id);
    }

    await tab(0);
    final ai = find.text('Hỏi Farmly AI');
    await tester.scrollUntilVisible(
      ai,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(ai);
    await checkpoint('chat-welcome');
    expect(find.byType(ChatWelcomeScreen), findsOneWidget);
    for (final (label, name) in const [
      ('Chi tiết dữ liệu', 'chat-data-sheet'),
      ('Lịch sử', 'chat-history-sheet'),
    ]) {
      final action = find.text(label);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await checkpoint(name);
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await checkpoint('back-$name');
    }
    final general = find.text('Dùng chế độ chung (không ngữ cảnh)');
    await tester.scrollUntilVisible(
      general,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(general);
    await checkpoint('chat-general-conversation-no-send');
    expect(find.byType(ChatConversationScreen), findsOneWidget);
    expect(
      tester
          .widget<ChatConversationScreen>(find.byType(ChatConversationScreen))
          .contextual,
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await checkpoint('back-general-conversation');
    await tester.binding.handlePopRoute();
    await checkpoint('back-chat');
    await tab(2);
    await tab(3);
    final addHarvest = find.text('Thêm thu hoạch');
    await tester.scrollUntilVisible(
      addHarvest,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(addHarvest);
    await checkpoint('harvest-add-sheet-no-save');
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await checkpoint('back-harvest-add-sheet');
    await tab(4);
    final logout = find.text('Đăng xuất');
    await tester.scrollUntilVisible(
      logout,
      180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.tap(logout);
    await checkpoint('logout-dialog-cancel-only');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Hủy')),
    );
    await checkpoint('back-logout-dialog');

    final sync = find.text('Trung tâm đồng bộ');
    // Logout lives below the sync card; reveal upwards after cancelling.
    await tester.scrollUntilVisible(
      sync,
      -180,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.tap(sync);
    await checkpoint('sync-preview-guarded');
    expect(find.byType(SyncCenterScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await checkpoint('back-sync');

    // Organization banner is the actual shell picker entrypoint.
    await tester.tap(find.text('Preview Organization').first);
    await checkpoint('organization-picker');
    expect(find.byType(OrganizationFlowScreen), findsOneWidget);
    // Organization flow has no visible back control; exercise the platform
    // back route event that Android users use on this screen.
    await tester.binding.handlePopRoute();
    await checkpoint('back-organization');
    await tab(1);

    // Authentication routes have no signed-in shell entrypoint. These are
    // visual-render checkpoints only; never submit forms or claim auth E2E.
    final router = GoRouter.of(tester.element(find.byType(FarmOverviewScreen)));
    const authSurfaces = <String, Type>{
      AppRoutes.splash: SplashScreen,
      AppRoutes.login: LoginScreen,
      AppRoutes.signup: SignUpScreen,
      AppRoutes.verifyEmail: VerifyEmailScreen,
      AppRoutes.emailVerified: EmailVerifiedScreen,
      AppRoutes.forgotPassword: ForgotPasswordScreen,
      AppRoutes.resetPassword: ResetPasswordScreen,
      AppRoutes.invitation: InvitationAcceptanceScreen,
    };
    for (final path in const [
      AppRoutes.splash,
      AppRoutes.login,
      AppRoutes.signup,
      AppRoutes.verifyEmail,
      AppRoutes.emailVerified,
      AppRoutes.forgotPassword,
      AppRoutes.resetPassword,
      AppRoutes.invitation,
    ]) {
      router.push<void>(path);
      await checkpoint('visual-only-$path');
      // Imperative native pushes need not rewrite the base browser URI.
      // Assert the real rendered destination, not URL reflection policy.
      expect(find.byType(authSurfaces[path]!), findsOneWidget);
      await tester.binding.handlePopRoute();
      await checkpoint('back-visual-only-$path');
    }

    await farmTop();
    final reset = find.byTooltip('Đặt lại khung nhìn');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await checkpoint('farm-final');
    expect(find.byType(ZoneScene), findsOneWidget);
  });
}
