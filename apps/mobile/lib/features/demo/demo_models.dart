/// In-memory demo domain models backing the Farmly FE screens. Values are
/// illustrative only; production screens will read typed repository state.
library;

/// Every resource screen cycles through these demo states (spec 02 §5).
enum DemoLoadState {
  success,
  loading,
  empty,
  recoverableError,
  offline,
  permissionDenied,
  pendingConflict;

  String get viLabel => switch (this) {
    DemoLoadState.success => 'Thành công',
    DemoLoadState.loading => 'Đang tải',
    DemoLoadState.empty => 'Trống',
    DemoLoadState.recoverableError => 'Lỗi (thử lại được)',
    DemoLoadState.offline => 'Ngoại tuyến',
    DemoLoadState.permissionDenied => 'Không có quyền',
    DemoLoadState.pendingConflict => 'Có xung đột',
  };
}

enum DemoAnimalCategory {
  cows,
  chickens,
  sheep,
  goats;

  String get viLabel => switch (this) {
    DemoAnimalCategory.cows => 'Bò',
    DemoAnimalCategory.chickens => 'Gà',
    DemoAnimalCategory.sheep => 'Cừu',
    DemoAnimalCategory.goats => 'Dê',
  };
}

enum DemoZoneKind { crop, livestock, water, storage, house }

/// Task-occurrence status (spec 04 taskOccurrence.status, phase 06):
/// open → done | skipped; cancelled is terminal. `in_progress` is reserved
/// by the contract and intentionally not modelled.
enum DemoTaskStatus { open, done, skipped, cancelled }

extension DemoTaskStatusLabel on DemoTaskStatus {
  String get viLabel => switch (this) {
    DemoTaskStatus.open => 'Chưa làm',
    DemoTaskStatus.done => 'Đã làm',
    DemoTaskStatus.skipped => 'Đã bỏ qua',
    DemoTaskStatus.cancelled => 'Đã huỷ',
  };
}

enum DemoHarvestStatus { confirmed, localPending, correctionPending, voided }

enum DemoSyncStatus { localPending, syncing, conflict }

/// Farm-scoped grant role (spec 04 §5.2 role matrix): workers may write
/// operational facts and *propose* corrections; managers approve them;
/// viewers are read-only.
enum DemoFarmRole { owner, manager, worker, viewer }

extension DemoFarmRoleLabel on DemoFarmRole {
  String get viLabel => switch (this) {
    DemoFarmRole.owner => 'Chủ trang trại',
    DemoFarmRole.manager => 'Quản lý',
    DemoFarmRole.worker => 'Công nhân',
    DemoFarmRole.viewer => 'Chỉ xem',
  };

  bool get canApproveCorrections =>
      this == DemoFarmRole.owner || this == DemoFarmRole.manager;

  bool get canWriteFacts =>
      this == DemoFarmRole.owner ||
      this == DemoFarmRole.manager ||
      this == DemoFarmRole.worker;
}

final class DemoOrganization {
  const DemoOrganization({required this.id, required this.name});

  final String id;
  final String name;
}

final class DemoFarm {
  const DemoFarm({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.location,
    required this.areaM2,
    required this.timezone,
  });

  final String id;
  final String organizationId;
  final String name;
  final String location;

  /// Canonical decimal string in square metres (API shape — spec 01/D-01).
  /// The UI converts to hectares with `formatAreaHectares`, never a double.
  final String areaM2;
  final String timezone;
}

final class DemoZone {
  const DemoZone({
    required this.id,
    required this.farmId,
    required this.name,
    required this.kind,
    required this.x,
    required this.y,
    this.subtitle,
  });

  final String id;
  final String farmId;
  final String name;
  final DemoZoneKind kind;

  /// Normalized hotspot position on the illustrated scene (0..1).
  final double x;
  final double y;
  final String? subtitle;
}

final class DemoCrop {
  const DemoCrop({
    required this.id,
    required this.zoneId,
    required this.species,
    this.sowedOn,
    this.expectedHarvestOn,
    this.manualProgressPercent,
    this.assessmentSource,
    this.ended = false,
  });

  final String id;
  final String zoneId;
  final String species;

  /// Civil dates (YYYY-MM-DD); null means "not recorded" — the UI must show
  /// a deliberate missing-date state, never a fabricated schedule (D-04).
  final String? sowedOn;
  final String? expectedHarvestOn;

  /// Manual assessment; null means "not yet assessed" (unknown state).
  final int? manualProgressPercent;
  final String? assessmentSource;

  /// Ended/archived planting — shown as a tombstone, no longer writable.
  final bool ended;
}

/// Water tank attached to a water zone (spec 02 §5, phase 05 step 5).
/// Quantities are canonical decimal strings — never floats (D-17).
final class DemoWaterTank {
  const DemoWaterTank({
    required this.id,
    required this.zoneId,
    required this.name,
    required this.capacityLitres,
    this.storedLitres,
    this.usedTodayLitres,
    this.source,
    this.asOf,
  });

  final String id;
  final String zoneId;
  final String name;
  final String capacityLitres;

  /// Latest manual reading; null means "no reading recorded" — the UI must
  /// show a deliberate unavailable state, never a fabricated live level.
  final String? storedLitres;
  final String? usedTodayLitres;
  final String? source;
  final String? asOf;

  DemoWaterTank copyWith({String? storedLitres, String? source, String? asOf}) =>
      DemoWaterTank(
        id: id,
        zoneId: zoneId,
        name: name,
        capacityLitres: capacityLitres,
        storedLitres: storedLitres ?? this.storedLitres,
        usedTodayLitres: usedTodayLitres,
        source: source ?? this.source,
        asOf: asOf ?? this.asOf,
      );
}

/// Task occurrence (spec 04 taskOccurrence): a deterministic materialization
/// of a template for a farm date + slot. Transitions go through
/// `taskOccurrence.transition` — never an in-place edit (phase 06).
final class DemoTask {
  const DemoTask({
    required this.id,
    required this.zoneId,
    required this.title,
    required this.timeLabel,
    this.status = DemoTaskStatus.open,
    this.assignee,
    this.overdue = false,
    this.completionNote,
  });

  final String id;
  final String zoneId;
  final String title;
  final String timeLabel;
  final DemoTaskStatus status;

  /// Assigned display name; null means unassigned — the UI states this
  /// explicitly rather than hiding it (spec 02 task row).
  final String? assignee;

  /// Past the farm-local due slot while still open (D-08).
  final bool overdue;
  final String? completionNote;

  bool get done => status == DemoTaskStatus.done;

  DemoTask copyWith({
    DemoTaskStatus? status,
    String? completionNote,
  }) =>
      DemoTask(
        id: id,
        zoneId: zoneId,
        title: title,
        timeLabel: timeLabel,
        status: status ?? this.status,
        assignee: assignee,
        overdue: overdue,
        completionNote: completionNote ?? this.completionNote,
      );
}

/// Herd mode (spec 04 herd.mode): `tracked` counts individually-registered
/// animals; `batch` is a single quantity with no per-animal records.
enum DemoHerdMode { tracked, batch }

extension DemoHerdModeLabel on DemoHerdMode {
  String get viLabel => switch (this) {
    DemoHerdMode.tracked => 'Theo dõi từng con',
    DemoHerdMode.batch => 'Đàn theo lô',
  };
}

/// Animal lifecycle status (spec 04 animal.status). Sold/deceased animals
/// stay visible as records but never count toward herd headcount (D-05).
enum DemoAnimalStatus { alive, sold, deceased }

extension DemoAnimalStatusLabel on DemoAnimalStatus {
  String get viLabel => switch (this) {
    DemoAnimalStatus.alive => 'Đang nuôi',
    DemoAnimalStatus.sold => 'Đã bán',
    DemoAnimalStatus.deceased => 'Đã chết',
  };
}

final class DemoHerd {
  const DemoHerd({
    required this.id,
    required this.farmId,
    required this.category,
    required this.species,
    required this.mode,
    this.batchQuantity,
  });

  final String id;
  final String farmId;
  final DemoAnimalCategory category;
  final String species;
  final DemoHerdMode mode;

  /// Headcount for a batch herd; always null for tracked herds — their
  /// headcount is derived from alive animals (D-05, no double counting).
  final int? batchQuantity;
}

final class DemoAnimal {
  const DemoAnimal({
    required this.id,
    required this.farmId,
    required this.herdId,
    required this.tag,
    required this.name,
    required this.category,
    this.birthDate,
    this.status = DemoAnimalStatus.alive,
  });

  final String id;
  final String farmId;

  /// Owning herd — a tracked animal contributes exactly once to its herd's
  /// headcount (D-05).
  final String herdId;
  final String tag;
  final String name;
  final DemoAnimalCategory category;

  /// Civil birth date (YYYY-MM-DD); null means "not recorded".
  final String? birthDate;
  final DemoAnimalStatus status;
}

final class DemoFeedingEntry {
  const DemoFeedingEntry({
    required this.id,
    required this.timeLabel,
    required this.category,
    required this.feedLabel,
    required this.total,
    required this.done,
  });

  final String id;
  final String timeLabel;
  final DemoAnimalCategory category;
  final String feedLabel;
  final int total;
  final int done;
}

/// A pending worker correction proposal on a harvest head (spec 04
/// harvest.correction.propose). The original record stays immutable — the
/// proposal rides alongside it until a manager applies or rejects it.
final class DemoHarvestCorrection {
  const DemoHarvestCorrection({
    required this.proposedQuantityKg,
    required this.reason,
    required this.proposedBy,
  });

  final String proposedQuantityKg;
  final String reason;
  final String proposedBy;
}

final class DemoHarvestRecord {
  const DemoHarvestRecord({
    required this.id,
    required this.cropLabel,
    required this.quantityKg,
    required this.harvestedOn,
    required this.status,
    this.correction,
    this.voidReason,
  });

  final String id;
  final String cropLabel;

  /// Exact base-10 decimal string (mirrors FarmlyDecimal semantics).
  final String quantityKg;
  final String harvestedOn;
  final DemoHarvestStatus status;

  /// Pending correction proposal; non-null only while
  /// `status == correctionPending`.
  final DemoHarvestCorrection? correction;

  /// Void reason; non-null only while `status == voided`.
  final String? voidReason;

  /// Confirmed kg that counts toward totals — voided records contribute
  /// nothing; a pending correction keeps counting the original value.
  bool get countsTowardTotals =>
      status == DemoHarvestStatus.confirmed ||
      status == DemoHarvestStatus.correctionPending;

  DemoHarvestRecord copyWith({
    DemoHarvestStatus? status,
    DemoHarvestCorrection? correction,
    String? voidReason,
    bool clearCorrection = false,
  }) =>
      DemoHarvestRecord(
        id: id,
        cropLabel: cropLabel,
        quantityKg: quantityKg,
        harvestedOn: harvestedOn,
        status: status ?? this.status,
        correction:
            clearCorrection ? null : (correction ?? this.correction),
        voidReason: voidReason ?? this.voidReason,
      );
}

final class DemoSyncItem {
  const DemoSyncItem({
    required this.id,
    required this.farmId,
    required this.operationType,
    required this.status,
    required this.localSummary,
    required this.updatedLabel,
    this.serverSummary,
    this.baseVersion,
    this.asOfLabel,
  });

  final String id;
  final String farmId;
  final String operationType;
  final DemoSyncStatus status;
  final String localSummary;
  final String? serverSummary;
  final int? baseVersion;
  final String updatedLabel;
  final String? asOfLabel;
}

final class DemoNotification {
  const DemoNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timeLabel,
  });

  final String id;
  final String title;
  final String body;
  final String timeLabel;
}

final class DemoSession {
  const DemoSession({required this.email, required this.displayName});

  final String email;
  final String displayName;
}

/// Manual moisture reading on a crop zone (spec 04 moistureReading.create).
/// Value is a base-10 decimal string; method/source/asOf are provenance —
/// manual readings are never averaged into a fabricated live sensor value.
final class DemoMoistureReading {
  const DemoMoistureReading({
    required this.id,
    required this.zoneId,
    required this.valuePercent,
    required this.method,
    required this.source,
    required this.asOf,
  });

  final String id;
  final String zoneId;
  final String valuePercent;

  /// e.g. 'đo tay', 'cảm biến nhập tay' — the method is recorded, not merged.
  final String method;
  final String source;

  /// Farm-local civil label for when the measurement was taken.
  final String asOf;
}

/// Water usage fact against a tank (spec 04 waterUsage.create) — separate
/// from a level reading; `usedTodayLitres` on the tank is the derived sum.
final class DemoWaterUsage {
  const DemoWaterUsage({
    required this.id,
    required this.tankId,
    required this.litres,
    required this.usedOn,
    this.purpose,
  });

  final String id;
  final String tankId;
  final String litres;
  final String usedOn;
  final String? purpose;
}

/// Animal production record (spec 04 productionRecord.create): milk litres,
/// egg count, or weight kg against a herd — quantities stay in their own
/// unit, never coerced.
final class DemoProductionRecord {
  const DemoProductionRecord({
    required this.id,
    required this.herdId,
    required this.product,
    required this.quantity,
    required this.unit,
    required this.recordedOn,
  });

  final String id;
  final String herdId;

  /// 'milk' | 'eggs' | 'weight' — the unit column carries lít/quả/kg.
  final String product;
  final String quantity;
  final String unit;
  final String recordedOn;
}

/// Weather snapshot provenance state (spec 04 WeatherSnapshot +
/// spec 06 D-15): a cached provider reading is either `fresh`, `stale`
/// (past its `validAt`), or `unavailable` — never fabricated.
enum DemoWeatherStatus { fresh, stale, unavailable }

/// Cached weather read for a farm's coarse grid. Carries provider + fetch
/// provenance so the UI can label it instead of implying a live sensor.
final class DemoWeatherSnapshot {
  const DemoWeatherSnapshot({
    required this.farmId,
    required this.provider,
    required this.temperatureC,
    required this.conditionLabel,
    required this.humidityPercent,
    required this.windLabel,
    required this.validAt,
    required this.fetchedAt,
    required this.status,
  });

  final String farmId;
  final String provider;
  final String temperatureC;
  final String conditionLabel;
  final String humidityPercent;
  final String windLabel;
  final String validAt;
  final String fetchedAt;
  final DemoWeatherStatus status;
}
