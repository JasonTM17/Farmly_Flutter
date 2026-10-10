import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'demo_models.dart';

/// In-memory demo catalog + Riverpod state for the Farmly FE screens.
/// Nothing here touches network, storage or the sync kernel; production
/// screens will consume typed repositories instead (phase 04/05 contracts).

const _orgHtxId = 'org-htx';
const _orgHoId = 'org-ho';
const farmBaViId = 'farm-bavi';
const _farmTrongTaiId = 'farm-trongtai';
const farmMoiId = 'farm-moi';

final class DemoDataState {
  const DemoDataState({
    required this.organizations,
    required this.farms,
    required this.zonesByFarm,
    required this.cropsByFarm,
    required this.tasksByZone,
    required this.herdsByFarm,
    required this.animalsByFarm,
    required this.tanksByZone,
    required this.feedingByFarm,
    required this.harvestsByFarm,
    required this.moistureByZone,
    required this.waterUsageByTank,
    required this.productionByHerd,
    required this.weatherByFarm,
    required this.syncItems,
    required this.notifications,
    required this.selectedOrganizationId,
    required this.selectedFarmId,
  });

  final List<DemoOrganization> organizations;
  final List<DemoFarm> farms;
  final Map<String, List<DemoZone>> zonesByFarm;
  final Map<String, List<DemoCrop>> cropsByFarm;
  final Map<String, List<DemoTask>> tasksByZone;
  final Map<String, List<DemoHerd>> herdsByFarm;
  final Map<String, List<DemoAnimal>> animalsByFarm;
  final Map<String, List<DemoWaterTank>> tanksByZone;
  final Map<String, List<DemoFeedingEntry>> feedingByFarm;
  final Map<String, List<DemoHarvestRecord>> harvestsByFarm;
  final Map<String, List<DemoMoistureReading>> moistureByZone;
  final Map<String, List<DemoWaterUsage>> waterUsageByTank;
  final Map<String, List<DemoProductionRecord>> productionByHerd;

  /// Latest cached weather read per farm — missing entry means no snapshot
  /// was ever fetched (unavailable), never a fabricated reading.
  final Map<String, DemoWeatherSnapshot> weatherByFarm;
  final List<DemoSyncItem> syncItems;
  final List<DemoNotification> notifications;
  final String? selectedOrganizationId;
  final String? selectedFarmId;

  DemoDataState copyWith({
    List<DemoOrganization>? organizations,
    List<DemoFarm>? farms,
    Map<String, List<DemoZone>>? zonesByFarm,
    Map<String, List<DemoCrop>>? cropsByFarm,
    Map<String, List<DemoTask>>? tasksByZone,
    Map<String, List<DemoHerd>>? herdsByFarm,
    Map<String, List<DemoAnimal>>? animalsByFarm,
    Map<String, List<DemoWaterTank>>? tanksByZone,
    Map<String, List<DemoFeedingEntry>>? feedingByFarm,
    Map<String, List<DemoHarvestRecord>>? harvestsByFarm,
    Map<String, List<DemoMoistureReading>>? moistureByZone,
    Map<String, List<DemoWaterUsage>>? waterUsageByTank,
    Map<String, List<DemoProductionRecord>>? productionByHerd,
    Map<String, DemoWeatherSnapshot>? weatherByFarm,
    List<DemoSyncItem>? syncItems,
    List<DemoNotification>? notifications,
    String? selectedOrganizationId,
    String? selectedFarmId,
    bool clearFarmSelection = false,
  }) {
    return DemoDataState(
      organizations: organizations ?? this.organizations,
      farms: farms ?? this.farms,
      zonesByFarm: zonesByFarm ?? this.zonesByFarm,
      cropsByFarm: cropsByFarm ?? this.cropsByFarm,
      tasksByZone: tasksByZone ?? this.tasksByZone,
      herdsByFarm: herdsByFarm ?? this.herdsByFarm,
      animalsByFarm: animalsByFarm ?? this.animalsByFarm,
      tanksByZone: tanksByZone ?? this.tanksByZone,
      feedingByFarm: feedingByFarm ?? this.feedingByFarm,
      harvestsByFarm: harvestsByFarm ?? this.harvestsByFarm,
      moistureByZone: moistureByZone ?? this.moistureByZone,
      waterUsageByTank: waterUsageByTank ?? this.waterUsageByTank,
      productionByHerd: productionByHerd ?? this.productionByHerd,
      weatherByFarm: weatherByFarm ?? this.weatherByFarm,
      syncItems: syncItems ?? this.syncItems,
      notifications: notifications ?? this.notifications,
      selectedOrganizationId:
          selectedOrganizationId ?? this.selectedOrganizationId,
      selectedFarmId: clearFarmSelection ? null : (selectedFarmId ?? this.selectedFarmId),
    );
  }
}

DemoFarm? farmById(DemoDataState state, String? farmId) {
  for (final farm in state.farms) {
    if (farm.id == farmId) return farm;
  }
  return null;
}

DemoOrganization? organizationById(DemoDataState state, String? orgId) {
  for (final org in state.organizations) {
    if (org.id == orgId) return org;
  }
  return null;
}

List<DemoFarm> farmsOfOrganization(DemoDataState state, String? orgId) => state
    .farms
    .where((farm) => farm.organizationId == orgId)
    .toList(growable: false);

List<DemoZone> zonesOfFarm(DemoDataState state, String? farmId) =>
    state.zonesByFarm[farmId] ?? const [];

List<DemoCrop> cropsOfFarm(DemoDataState state, String? farmId) =>
    state.cropsByFarm[farmId] ?? const [];

List<DemoCrop> cropsOfZone(DemoDataState state, String zoneId) {
  for (final entry in state.cropsByFarm.entries) {
    final inZone = entry.value
        .where((crop) => crop.zoneId == zoneId)
        .toList(growable: false);
    if (inZone.isNotEmpty) return inZone;
  }
  return const [];
}

List<DemoHerd> herdsOfFarm(DemoDataState state, String? farmId) =>
    state.herdsByFarm[farmId] ?? const [];

List<DemoAnimal> animalsOfFarm(DemoDataState state, String? farmId) =>
    state.animalsByFarm[farmId] ?? const [];

List<DemoAnimal> animalsOfHerd(DemoDataState state, String herdId) {
  for (final entry in state.animalsByFarm.entries) {
    final inHerd = entry.value
        .where((animal) => animal.herdId == herdId)
        .toList(growable: false);
    if (inHerd.isNotEmpty) return inHerd;
  }
  return const [];
}

/// Herd headcount (D-05): a batch herd contributes its declared quantity;
/// a tracked herd counts alive animals only — sold/deceased records stay
/// visible but never count, and no animal is counted twice.
int herdHeadcount(DemoDataState state, DemoHerd herd) => switch (herd.mode) {
  DemoHerdMode.batch => herd.batchQuantity ?? 0,
  DemoHerdMode.tracked => animalsOfHerd(state, herd.id)
      .where((animal) => animal.status == DemoAnimalStatus.alive)
      .length,
};

/// Farm livestock headcount: the sum over herds — batch quantities plus
/// tracked alive counts — so batch and tracked members never mix or double
/// count (D-05).
int farmLivestockHeadcount(DemoDataState state, String? farmId) =>
    herdsOfFarm(
      state,
      farmId,
    ).fold(0, (sum, herd) => sum + herdHeadcount(state, herd));

/// Headcount for one category across the farm's herds (batch quantity or
/// tracked-alive count, per herd mode).
int categoryLivestockHeadcount(
  DemoDataState state,
  String? farmId,
  DemoAnimalCategory category,
) => herdsOfFarm(state, farmId)
    .where((herd) => herd.category == category)
    .fold(0, (sum, herd) => sum + herdHeadcount(state, herd));

DemoWaterTank? tankOfZone(DemoDataState state, String? zoneId) =>
    state.tanksByZone[zoneId]?.firstOrNull;

List<DemoFeedingEntry> feedingOfFarm(DemoDataState state, String? farmId) =>
    state.feedingByFarm[farmId] ?? const [];

List<DemoHarvestRecord> harvestsOfFarm(DemoDataState state, String? farmId) =>
    state.harvestsByFarm[farmId] ?? const [];

List<DemoTask> tasksOfZone(DemoDataState state, String zoneId) =>
    state.tasksByZone[zoneId] ?? const [];

/// Latest moisture reading per zone, newest first — null means no manual
/// reading yet, which the UI renders as an explicit "chưa đo" state.
DemoMoistureReading? latestMoistureOfZone(DemoDataState state, String zoneId) =>
    state.moistureByZone[zoneId]?.firstOrNull;

List<DemoWaterUsage> waterUsageOfTank(DemoDataState state, String tankId) =>
    state.waterUsageByTank[tankId] ?? const [];

List<DemoProductionRecord> productionOfHerd(
  DemoDataState state,
  String herdId,
) => state.productionByHerd[herdId] ?? const [];

/// Latest cached weather snapshot for the farm — null means the provider
/// has never produced a reading for this scope (unavailable state, D-15).
DemoWeatherSnapshot? weatherOfFarm(DemoDataState state, String? farmId) =>
    state.weatherByFarm[farmId];

/// True while a demo outbox entry is still local-pending (spec 02 §7 pending
/// visibility — e.g. the "Chờ đồng bộ" chip on a just-assessed crop).
bool syncItemPending(DemoDataState state, String syncItemId) => state.syncItems
    .any((i) => i.id == syncItemId && i.status == DemoSyncStatus.localPending);

/// Operations health (spec 06 D-14): done/eligible task occurrences across
/// the farm's zones. Eligible = done|skipped (open/future/cancelled are
/// excluded from the denominator; pending transitions don't inflate the
/// numerator). Fewer than 5 eligible occurrences yields null = unknown,
/// never a fake score.
double? operationsHealthOf(DemoDataState state) {
  final farmId = state.selectedFarmId;
  if (farmId == null) return null;
  var eligible = 0;
  var done = 0;
  for (final zone in zonesOfFarm(state, farmId)) {
    for (final task in state.tasksByZone[zone.id] ?? const <DemoTask>[]) {
      switch (task.status) {
        case DemoTaskStatus.done:
          done += 1;
          eligible += 1;
        case DemoTaskStatus.skipped:
          eligible += 1;
        case DemoTaskStatus.open || DemoTaskStatus.cancelled:
          break;
      }
    }
  }
  if (eligible < 5) return null;
  return done / eligible;
}

class DemoDataNotifier extends Notifier<DemoDataState> {
  @override
  DemoDataState build() => _seed();

  void selectOrganization(String organizationId) {
    final firstFarm = farmsOfOrganization(state, organizationId).firstOrNull;
    state = state.copyWith(
      selectedOrganizationId: organizationId,
      selectedFarmId: firstFarm?.id,
      clearFarmSelection: firstFarm == null,
    );
  }

  void selectFarm(String farmId) {
    final farm = farmById(state, farmId);
    if (farm == null) return;
    state = state.copyWith(
      selectedOrganizationId: farm.organizationId,
      selectedFarmId: farm.id,
    );
  }

  /// Occurrence transition (spec 04 taskOccurrence.transition): open → done,
  /// open → skipped, done/skipped → open (reopen). Terminal `cancelled` is
  /// not reachable from the checklist UI. Each transition enqueues a
  /// `taskOccurrence.transition` intent — the write stays local-pending.
  void transitionTask(
    String zoneId,
    String taskId,
    DemoTaskStatus target, {
    String? note,
  }) {
    final tasks = state.tasksByZone[zoneId];
    final farmId = state.selectedFarmId;
    if (tasks == null || farmId == null) return;
    DemoTask? updatedTask;
    final updated = tasks.map((task) {
      if (task.id != taskId) return task;
      final next = switch (task.status) {
        DemoTaskStatus.open => switch (target) {
            DemoTaskStatus.done || DemoTaskStatus.skipped => target,
            _ => task.status,
          },
        DemoTaskStatus.done || DemoTaskStatus.skipped =>
          target == DemoTaskStatus.open ? DemoTaskStatus.open : task.status,
        DemoTaskStatus.cancelled => task.status,
      };
      updatedTask = task.copyWith(
        status: next,
        completionNote: note ?? task.completionNote,
      );
      return updatedTask!;
    }).toList(growable: false);
    final task = updatedTask;
    if (task == null || task.status == DemoTaskStatus.open && target == DemoTaskStatus.open) {
      return;
    }
    final item = DemoSyncItem(
      id: 'sync-transition-$taskId-${task.status.name}',
      farmId: farmId,
      operationType: 'taskOccurrence.transition',
      status: DemoSyncStatus.localPending,
      localSummary:
          '${task.title}: ${task.status.viLabel.toLowerCase()}',
      updatedLabel: 'Vừa lưu',
    );
    final others = state.syncItems
        .where((item) => item.id != 'sync-transition-$taskId-${task.status.name}')
        .toList(growable: false);
    state = state.copyWith(
      tasksByZone: {...state.tasksByZone, zoneId: updated},
      syncItems: [item, ...others],
    );
  }

  /// Records a manual crop assessment. The write stays local-pending: a
  /// `planting.update` intent enters the demo outbox so the change is visible
  /// as unsynced until the demo sync clears it (spec 02 §5/§7).
  void setCropAssessment(String cropId, int percent) {
    final farmId = state.selectedFarmId;
    final crops = state.cropsByFarm[farmId];
    if (crops == null) return;
    final clamped = percent.clamp(0, 100);
    final updated = crops
        .map(
          (crop) => crop.id == cropId
              ? DemoCrop(
                  id: crop.id,
                  zoneId: crop.zoneId,
                  species: crop.species,
                  sowedOn: crop.sowedOn,
                  expectedHarvestOn: crop.expectedHarvestOn,
                  manualProgressPercent: clamped,
                  assessmentSource: 'Đánh giá thủ công của bạn',
                  ended: crop.ended,
                )
              : crop,
        )
        .toList(growable: false);
    final species = updated
        .where((crop) => crop.id == cropId)
        .firstOrNull
        ?.species;
    final item = DemoSyncItem(
      id: 'sync-assess-$cropId',
      farmId: farmId!,
      operationType: 'planting.update',
      status: DemoSyncStatus.localPending,
      localSummary: 'Đánh giá ${species ?? cropId}: $clamped%',
      updatedLabel: 'Vừa lưu',
    );
    final others = state.syncItems
        .where((item) => item.id != 'sync-assess-$cropId')
        .toList(growable: false);
    state = state.copyWith(
      cropsByFarm: {...state.cropsByFarm, farmId: updated},
      syncItems: [item, ...others],
    );
  }

  /// Creates a zone on the given farm (demo local write; backs the My Farm
  /// no-zone CTA "Tạo vùng đầu tiên", spec 02 §5). A `zone.create` intent
  /// enters the demo outbox so the write is visible as local-pending.
  void addZone(DemoZone zone) {
    final existing = state.zonesByFarm[zone.farmId] ?? const <DemoZone>[];
    final item = DemoSyncItem(
      id: 'sync-${zone.id}',
      farmId: zone.farmId,
      operationType: 'zone.create',
      status: DemoSyncStatus.localPending,
      localSummary: 'Tạo vùng ${zone.name}',
      updatedLabel: 'Vừa lưu',
    );
    state = state.copyWith(
      zonesByFarm: {
        ...state.zonesByFarm,
        zone.farmId: [...existing, zone],
      },
      syncItems: [item, ...state.syncItems],
    );
  }

  void addHarvest(DemoHarvestRecord record) {
    final farmId = state.selectedFarmId;
    if (farmId == null) return;
    final existing = state.harvestsByFarm[farmId] ?? const <DemoHarvestRecord>[];
    final updated = <DemoHarvestRecord>[record, ...existing];
    final item = DemoSyncItem(
      id: 'sync-${record.id}',
      farmId: farmId,
      operationType: 'harvest.create',
      status: DemoSyncStatus.localPending,
      localSummary:
          '${record.cropLabel}: ${record.quantityKg} kg ngày ${record.harvestedOn}',
      updatedLabel: 'Vừa lưu',
    );
    state = state.copyWith(
      harvestsByFarm: {...state.harvestsByFarm, farmId: updated},
      syncItems: [item, ...state.syncItems],
    );
  }

  /// Appends a locally-created task (demo write — backs the Smart watering
  /// wizard and the zone task entry, phase 05 steps 3/5, D-18). Task planning
  /// only, no actuation. A `task.create` intent enters the demo outbox so the
  /// write is visible as local-pending (spec 02 §5/§7).
  void addTask(DemoTask task) {
    final existing = state.tasksByZone[task.zoneId] ?? const <DemoTask>[];
    final farmId = state.selectedFarmId;
    final item = farmId == null
        ? null
        : DemoSyncItem(
            id: 'sync-${task.id}',
            farmId: farmId,
            operationType: 'task.create',
            status: DemoSyncStatus.localPending,
            localSummary: task.title,
            updatedLabel: 'Vừa lưu',
          );
    state = state.copyWith(
      tasksByZone: {
        ...state.tasksByZone,
        task.zoneId: [...existing, task],
      },
      syncItems: item == null ? state.syncItems : [item, ...state.syncItems],
    );
  }

  /// Records a manual tank reading (D-17): exact litres + a provenance label.
  /// A `waterTank.update` intent enters the demo outbox so the reading is
  /// visible as local-pending (spec 02 §7).
  void recordTankReading(String zoneId, String litres, String asOf) {
    final tank = tankOfZone(state, zoneId);
    final farmId = state.selectedFarmId;
    if (tank == null || farmId == null) return;
    final updated = tank.copyWith(
      storedLitres: litres,
      source: 'đồng hồ đọc tay',
      asOf: asOf,
    );
    final item = DemoSyncItem(
      id: 'sync-reading-${tank.id}',
      farmId: farmId,
      operationType: 'waterTank.update',
      status: DemoSyncStatus.localPending,
      localSummary: 'Số đo ${tank.name}: $litres lít',
      updatedLabel: 'Vừa lưu',
    );
    state = state.copyWith(
      tanksByZone: {
        ...state.tanksByZone,
        zoneId: [updated],
      },
      syncItems: [item, ...state.syncItems],
    );
  }

  /// Worker proposal on a confirmed harvest (spec 04
  /// harvest.correction.propose): the original record stays immutable —
  /// the proposal rides on the head until a manager applies or rejects it.
  /// `harvest.correction.propose` intent enters the outbox as local-pending.
  void proposeHarvestCorrection(
    String recordId, {
    required String proposedQuantityKg,
    required String reason,
    required String proposedBy,
  }) {
    final farmId = state.selectedFarmId;
    final records = state.harvestsByFarm[farmId];
    if (farmId == null || records == null) return;
    final updated = records.map((record) {
      if (record.id != recordId ||
          record.status != DemoHarvestStatus.confirmed) {
        return record;
      }
      return record.copyWith(
        status: DemoHarvestStatus.correctionPending,
        correction: DemoHarvestCorrection(
          proposedQuantityKg: proposedQuantityKg,
          reason: reason,
          proposedBy: proposedBy,
        ),
      );
    }).toList(growable: false);
    final record = updated
        .where((candidate) => candidate.id == recordId)
        .firstOrNull;
    if (record == null ||
        record.status != DemoHarvestStatus.correctionPending) {
      return;
    }
    final item = DemoSyncItem(
      id: 'sync-correct-$recordId',
      farmId: farmId,
      operationType: 'harvest.correction.propose',
      status: DemoSyncStatus.localPending,
      localSummary:
          'Đề xuất chỉnh ${record.cropLabel}: '
          '${record.quantityKg} → $proposedQuantityKg kg',
      updatedLabel: 'Vừa lưu',
    );
    final others = state.syncItems
        .where((item) => item.id != 'sync-correct-$recordId')
        .toList(growable: false);
    state = state.copyWith(
      harvestsByFarm: {...state.harvestsByFarm, farmId: updated},
      syncItems: [item, ...others],
    );
  }

  /// Manager applies a pending correction (spec 04 harvest.correction.apply):
  /// the head's effective quantity becomes the proposed value, the original
  /// stays in the immutable record history (not shown in demo state).
  void applyHarvestCorrection(String recordId) {
    final farmId = state.selectedFarmId;
    final records = state.harvestsByFarm[farmId];
    if (farmId == null || records == null) return;
    String? summary;
    final updated = records.map((record) {
      final proposal = record.correction;
      if (record.id != recordId ||
          record.status != DemoHarvestStatus.correctionPending ||
          proposal == null) {
        return record;
      }
      summary =
          '${record.cropLabel}: ${record.quantityKg} → '
          '${proposal.proposedQuantityKg} kg';
      return DemoHarvestRecord(
        id: record.id,
        cropLabel: record.cropLabel,
        quantityKg: proposal.proposedQuantityKg,
        harvestedOn: record.harvestedOn,
        status: DemoHarvestStatus.confirmed,
      );
    }).toList(growable: false);
    if (summary == null) return;
    final item = DemoSyncItem(
      id: 'sync-apply-$recordId',
      farmId: farmId,
      operationType: 'harvest.correction.apply',
      status: DemoSyncStatus.localPending,
      localSummary: 'Áp dụng chỉnh sửa — $summary',
      updatedLabel: 'Vừa lưu',
    );
    final others = state.syncItems
        .where((item) => item.id != 'sync-apply-$recordId')
        .toList(growable: false);
    state = state.copyWith(
      harvestsByFarm: {...state.harvestsByFarm, farmId: updated},
      syncItems: [item, ...others],
    );
  }

  /// Manager rejects a pending correction — the record returns to confirmed
  /// with its original quantity untouched.
  void rejectHarvestCorrection(String recordId) {
    final farmId = state.selectedFarmId;
    final records = state.harvestsByFarm[farmId];
    if (farmId == null || records == null) return;
    final updated = records.map((record) {
      if (record.id != recordId ||
          record.status != DemoHarvestStatus.correctionPending) {
        return record;
      }
      return record.copyWith(
        status: DemoHarvestStatus.confirmed,
        clearCorrection: true,
      );
    }).toList(growable: false);
    state = state.copyWith(
      harvestsByFarm: {...state.harvestsByFarm, farmId: updated},
    );
  }

  /// Voids a harvest record (spec 04 harvest.void): the row stays visible
  /// as an audit tombstone but no longer counts toward totals. Requires a
  /// reason — the void is itself an append-only fact.
  void voidHarvest(String recordId, {required String reason}) {
    final farmId = state.selectedFarmId;
    final records = state.harvestsByFarm[farmId];
    if (farmId == null || records == null) return;
    String? summary;
    final updated = records.map((record) {
      if (record.id != recordId ||
          record.status == DemoHarvestStatus.voided ||
          record.status == DemoHarvestStatus.localPending) {
        return record;
      }
      summary = '${record.cropLabel}: ${record.quantityKg} kg — $reason';
      return record.copyWith(
        status: DemoHarvestStatus.voided,
        voidReason: reason,
        clearCorrection: true,
      );
    }).toList(growable: false);
    if (summary == null) return;
    final item = DemoSyncItem(
      id: 'sync-void-$recordId',
      farmId: farmId,
      operationType: 'harvest.void',
      status: DemoSyncStatus.localPending,
      localSummary: 'Huỷ bản ghi — $summary',
      updatedLabel: 'Vừa lưu',
    );
    final others = state.syncItems
        .where((item) => item.id != 'sync-void-$recordId')
        .toList(growable: false);
    state = state.copyWith(
      harvestsByFarm: {...state.harvestsByFarm, farmId: updated},
      syncItems: [item, ...others],
    );
  }

  /// Manual moisture reading on a crop zone (spec 04 moistureReading.create):
  /// percent + method + source are stored as recorded — never averaged into
  /// a fabricated live value. `moistureReading.create` intent, local-pending.
  void recordMoisture(
    String zoneId, {
    required String valuePercent,
    required String method,
    required String asOf,
  }) {
    final farmId = state.selectedFarmId;
    if (farmId == null) return;
    final id = 'moisture-${DateTime.now().microsecondsSinceEpoch}';
    final reading = DemoMoistureReading(
      id: id,
      zoneId: zoneId,
      valuePercent: valuePercent,
      method: method,
      source: 'đồng hồ đọc tay',
      asOf: asOf,
    );
    final existing = state.moistureByZone[zoneId] ?? const [];
    final item = DemoSyncItem(
      id: 'sync-$id',
      farmId: farmId,
      operationType: 'moistureReading.create',
      status: DemoSyncStatus.localPending,
      localSummary: 'Độ ẩm $valuePercent% ($method)',
      updatedLabel: 'Vừa lưu',
    );
    state = state.copyWith(
      moistureByZone: {
        ...state.moistureByZone,
        zoneId: [reading, ...existing],
      },
      syncItems: [item, ...state.syncItems],
    );
  }

  /// Water usage against a tank (spec 04 waterUsage.create) — a fact separate
  /// from a level reading. `usedTodayLitres` on the tank is updated from the
  /// fact list; `waterUsage.create` intent enters the outbox.
  void recordWaterUsage(
    String zoneId, {
    required String litres,
    String? purpose,
  }) {
    final tank = tankOfZone(state, zoneId);
    final farmId = state.selectedFarmId;
    if (tank == null || farmId == null) return;
    final id = 'usage-${DateTime.now().microsecondsSinceEpoch}';
    final usage = DemoWaterUsage(
      id: id,
      tankId: tank.id,
      litres: litres,
      usedOn: 'hôm nay',
      purpose: purpose,
    );
    final existing = state.waterUsageByTank[tank.id] ?? const [];
    final usedSum = [usage, ...existing].fold<double>(
      0,
      (sum, entry) => sum + (double.tryParse(entry.litres) ?? 0),
    );
    final updated = DemoWaterTank(
      id: tank.id,
      zoneId: tank.zoneId,
      name: tank.name,
      capacityLitres: tank.capacityLitres,
      storedLitres: tank.storedLitres,
      usedTodayLitres: usedSum == usedSum.roundToDouble()
          ? usedSum.round().toString()
          : usedSum.toString(),
      source: tank.source,
      asOf: tank.asOf,
    );
    final item = DemoSyncItem(
      id: 'sync-$id',
      farmId: farmId,
      operationType: 'waterUsage.create',
      status: DemoSyncStatus.localPending,
      localSummary:
          'Đã dùng $litres lít${purpose == null ? '' : ' — $purpose'} '
          'từ ${tank.name}',
      updatedLabel: 'Vừa lưu',
    );
    state = state.copyWith(
      waterUsageByTank: {
        ...state.waterUsageByTank,
        tank.id: [usage, ...existing],
      },
      tanksByZone: {...state.tanksByZone, zoneId: [updated]},
      syncItems: [item, ...state.syncItems],
    );
  }

  /// Animal production record (spec 04 productionRecord.create): milk/eggs/
  /// weight appended as an immutable fact — corrections are new records, not
  /// edits. `productionRecord.create` intent enters the outbox.
  void recordProduction(
    String herdId, {
    required String product,
    required String quantity,
    required String unit,
  }) {
    final farmId = state.selectedFarmId;
    if (farmId == null) return;
    final herd = state.herdsByFarm[farmId]
        ?.where((candidate) => candidate.id == herdId)
        .firstOrNull;
    if (herd == null) return;
    final id = 'prod-${DateTime.now().microsecondsSinceEpoch}';
    final record = DemoProductionRecord(
      id: id,
      herdId: herdId,
      product: product,
      quantity: quantity,
      unit: unit,
      recordedOn: 'hôm nay',
    );
    final existing = state.productionByHerd[herdId] ?? const [];
    final item = DemoSyncItem(
      id: 'sync-$id',
      farmId: farmId,
      operationType: 'productionRecord.create',
      status: DemoSyncStatus.localPending,
      localSummary:
          '$product ${herd.species}: $quantity $unit',
      updatedLabel: 'Vừa lưu',
    );
    state = state.copyWith(
      productionByHerd: {
        ...state.productionByHerd,
        herdId: [record, ...existing],
      },
      syncItems: [item, ...state.syncItems],
    );
  }

  /// Batch herd movement delta (spec 04 livestockMovement.create): an
  /// in/out/loss fact adjusts `batchQuantity` by signed delta — headcount is
  /// never replaced by a total (D-05/06).
  void recordBatchMovement(String herdId, int delta, String reason) {
    final farmId = state.selectedFarmId;
    final herds = state.herdsByFarm[farmId];
    if (farmId == null || herds == null) return;
    String? summary;
    final updated = herds.map((herd) {
      if (herd.id != herdId || herd.mode != DemoHerdMode.batch) return herd;
      final next = (herd.batchQuantity ?? 0) + delta;
      if (next < 0) return herd;
      summary =
          '${herd.species}: ${delta >= 0 ? '+' : ''}$delta con ($reason)';
      return DemoHerd(
        id: herd.id,
        farmId: herd.farmId,
        category: herd.category,
        species: herd.species,
        mode: herd.mode,
        batchQuantity: next,
      );
    }).toList(growable: false);
    if (summary == null) return;
    final item = DemoSyncItem(
      id: 'sync-move-$herdId-${DateTime.now().microsecondsSinceEpoch}',
      farmId: farmId,
      operationType: 'livestockMovement.create',
      status: DemoSyncStatus.localPending,
      localSummary: 'Nhập/xuất đàn — $summary',
      updatedLabel: 'Vừa lưu',
    );
    state = state.copyWith(
      herdsByFarm: {...state.herdsByFarm, farmId: updated},
      syncItems: [item, ...state.syncItems],
    );
  }

  void markSyncItemSynced(String itemId) {
    // Demo only: the item leaves the outbox view once synced.
    removeSyncItem(itemId);
  }

  void removeSyncItem(String itemId) {
    state = state.copyWith(
      syncItems: state.syncItems
          .where((item) => item.id != itemId)
          .toList(growable: false),
    );
  }

  /// Keeps the local proposal as an authorized replacement intent (spec 02 §7):
  /// the conflict entry becomes a local-pending replacement operation.
  void resolveConflictWithReplacement(String itemId) {
    final item = state.syncItems
        .where((candidate) => candidate.id == itemId)
        .firstOrNull;
    if (item == null || item.status != DemoSyncStatus.conflict) return;
    final replaced = DemoSyncItem(
      id: item.id,
      farmId: item.farmId,
      operationType: item.operationType,
      status: DemoSyncStatus.localPending,
      localSummary: item.localSummary,
      updatedLabel: 'Intent thay thế đã tạo',
    );
    state = state.copyWith(
      syncItems: state.syncItems
          .map((candidate) => candidate.id == itemId ? replaced : candidate)
          .toList(growable: false),
    );
  }
}

final demoDataProvider = NotifierProvider<DemoDataNotifier, DemoDataState>(
  DemoDataNotifier.new,
);

final selectedFarmProvider = Provider<DemoFarm?>(
  (ref) => farmById(ref.watch(demoDataProvider), ref.watch(demoDataProvider).selectedFarmId),
);

final selectedOrganizationProvider = Provider<DemoOrganization?>(
  (ref) => organizationById(
    ref.watch(demoDataProvider),
    ref.watch(demoDataProvider).selectedOrganizationId,
  ),
);

final farmsOfSelectedOrgProvider = Provider<List<DemoFarm>>(
  (ref) =>
      farmsOfOrganization(ref.watch(demoDataProvider), ref.watch(demoDataProvider).selectedOrganizationId),
);

class DemoScreenStateNotifier
    extends Notifier<Map<String, DemoLoadState>> {
  @override
  Map<String, DemoLoadState> build() => const <String, DemoLoadState>{};

  void set(String screenKey, DemoLoadState value) {
    state = {...state, screenKey: value};
  }

  void reset(String screenKey) {
    final next = {...state}..remove(screenKey);
    state = next;
  }

  void cycle(String screenKey) {
    final current = state[screenKey];
    final values = DemoLoadState.values;
    final next = values[((current?.index ?? -1) + 1) % values.length];
    set(screenKey, next);
  }
}

final demoScreenStateProvider =
    NotifierProvider<DemoScreenStateNotifier, Map<String, DemoLoadState>>(
      DemoScreenStateNotifier.new,
    );

/// Effective screen state: explicit demo override wins, otherwise empty data
/// yields the empty state (spec 02 §5: every screen shows all states).
DemoLoadState effectiveDemoState(
  WidgetRef ref,
  String screenKey, {
  required bool dataEmpty,
}) {
  final override = ref.watch(demoScreenStateProvider)[screenKey];
  if (override != null) return override;
  return dataEmpty ? DemoLoadState.empty : DemoLoadState.success;
}

final class AiConsentState {
  const AiConsentState({
    required this.contextualAccepted,
    required this.decisionRecorded,
    required this.revision,
    required this.usageState,
    required this.inputTokensThisMonth,
    required this.outputTokensThisMonth,
  });

  const AiConsentState.initial()
    : contextualAccepted = false,
      decisionRecorded = false,
      revision = 1,
      usageState = 'known',
      inputTokensThisMonth = 1240,
      outputTokensThisMonth = 3860;

  final bool contextualAccepted;

  /// Whether the user already picked accept / general mode this session.
  final bool decisionRecorded;
  final int revision;
  final String usageState;
  final int inputTokensThisMonth;
  final int outputTokensThisMonth;

  AiConsentState copyWith({
    bool? contextualAccepted,
    bool? decisionRecorded,
    int? revision,
  }) => AiConsentState(
    contextualAccepted: contextualAccepted ?? this.contextualAccepted,
    decisionRecorded: decisionRecorded ?? this.decisionRecorded,
    revision: revision ?? this.revision,
    usageState: usageState,
    inputTokensThisMonth: inputTokensThisMonth,
    outputTokensThisMonth: outputTokensThisMonth,
  );
}

class AiConsentNotifier extends Notifier<AiConsentState> {
  @override
  AiConsentState build() => const AiConsentState.initial();

  void acceptContextual() =>
      state = state.copyWith(
        contextualAccepted: true,
        decisionRecorded: true,
        revision: state.revision + 1,
      );

  void chooseGeneralMode() =>
      state = state.copyWith(
        contextualAccepted: false,
        decisionRecorded: true,
        revision: state.revision + 1,
      );
}

final aiConsentProvider = NotifierProvider<AiConsentNotifier, AiConsentState>(
  AiConsentNotifier.new,
);

class DemoSessionNotifier extends Notifier<DemoSession?> {
  @override
  DemoSession? build() => null;

  /// Demo sign-in: the session lives only in memory (offline demo session).
  void signIn(String email) {
    final prefix = email.split('@').first;
    final name = prefix.isEmpty
        ? 'Nông dân'
        : '${prefix[0].toUpperCase()}${prefix.substring(1)}';
    state = DemoSession(email: email, displayName: name);
  }

  void signOut() => state = null;
}

final demoSessionProvider =
    NotifierProvider<DemoSessionNotifier, DemoSession?>(
      DemoSessionNotifier.new,
    );

/// Farm-scoped demo grant role (spec 04 §5.2 role matrix) — drives role-aware
/// controls: workers propose corrections, managers apply, viewers read only.
/// Lives apart from the session so the preview/tests can exercise boundaries
/// without a signed-in user; defaults to manager (full demo controls).
class DemoFarmRoleNotifier extends Notifier<DemoFarmRole> {
  @override
  DemoFarmRole build() => DemoFarmRole.manager;

  void set(DemoFarmRole role) => state = role;
}

final demoFarmRoleProvider =
    NotifierProvider<DemoFarmRoleNotifier, DemoFarmRole>(
      DemoFarmRoleNotifier.new,
    );

DemoDataState _seed() {
  const organizations = [
    DemoOrganization(id: _orgHtxId, name: 'HTX Nông sản Hòa Bình'),
    DemoOrganization(id: _orgHoId, name: 'Hộ Trọng Tài'),
  ];

  const farms = [
    DemoFarm(
      id: farmBaViId,
      organizationId: _orgHtxId,
      name: 'Nông trại Ba Vì',
      location: 'Ba Vì, Hà Nội',
      areaM2: '32000',
      timezone: 'Asia/Ho_Chi_Minh',
    ),
    DemoFarm(
      id: farmMoiId,
      organizationId: _orgHtxId,
      name: 'Nông trại mới Tuyên Quang',
      location: 'Sơn Dương, Tuyên Quang',
      areaM2: '10000',
      timezone: 'Asia/Ho_Chi_Minh',
    ),
    DemoFarm(
      id: _farmTrongTaiId,
      organizationId: _orgHoId,
      name: 'Vườn nhà Trọng Tài',
      location: 'Yên Phong, Bắc Ninh',
      areaM2: '4000',
      timezone: 'Asia/Ho_Chi_Minh',
    ),
  ];

  const zonesBaVi = [
    DemoZone(
      id: 'zone-rau-an-la',
      farmId: farmBaViId,
      name: 'Rau ăn lá',
      kind: DemoZoneKind.crop,
      x: 0.24,
      y: 0.42,
      subtitle: 'Luống ngoài đồng',
    ),
    DemoZone(
      id: 'zone-ca-chua',
      farmId: farmBaViId,
      name: 'Cà chua giàn',
      kind: DemoZoneKind.crop,
      x: 0.58,
      y: 0.34,
      subtitle: 'Nhà lưới B',
    ),
    DemoZone(
      id: 'zone-chuong-ga',
      farmId: farmBaViId,
      name: 'Chuồng gà',
      kind: DemoZoneKind.livestock,
      x: 0.78,
      y: 0.62,
      subtitle: 'Chuồng nhỏ phía đông',
    ),
    DemoZone(
      id: 'zone-bon-nuoc',
      farmId: farmBaViId,
      name: 'Bồn nước',
      kind: DemoZoneKind.water,
      x: 0.34,
      y: 0.7,
      subtitle: 'Bể 5000 lít',
    ),
  ];

  const zonesTrongTai = [
    DemoZone(
      id: 'zone-vuon-rau',
      farmId: _farmTrongTaiId,
      name: 'Vườn rau sau nhà',
      kind: DemoZoneKind.crop,
      x: 0.4,
      y: 0.5,
      subtitle: 'Luống nhỏ',
    ),
  ];

  final cropsBaVi = const [
    DemoCrop(
      id: 'crop-cai-ngot',
      zoneId: 'zone-rau-an-la',
      species: 'Cải ngọt',
      sowedOn: '2026-08-20',
      expectedHarvestOn: '2026-11-05',
      manualProgressPercent: 62,
      assessmentSource: 'Đánh giá thủ công của bạn',
    ),
    DemoCrop(
      id: 'crop-ca-chua',
      zoneId: 'zone-ca-chua',
      species: 'Cà chua',
      sowedOn: '2026-09-10',
      // No expected harvest yet — the UI shows a deliberate missing-date
      // state instead of guessing one (D-04).
    ),
    DemoCrop(
      id: 'crop-cai-xanh-cu',
      zoneId: 'zone-rau-an-la',
      species: 'Cải xanh vụ trước',
      sowedOn: '2026-05-12',
      expectedHarvestOn: '2026-07-30',
      manualProgressPercent: 100,
      assessmentSource: 'Đánh giá thủ công của bạn',
      ended: true,
    ),
  ];

  const cropsTrongTai = [
    DemoCrop(
      id: 'crop-muong-tay',
      zoneId: 'zone-vuon-rau',
      species: 'Mồng tây',
      sowedOn: '2026-09-01',
      expectedHarvestOn: '2026-10-20',
      manualProgressPercent: 80,
      assessmentSource: 'Đánh giá thủ công của bạn',
    ),
  ];

  final tasksByZone = <String, List<DemoTask>>{
    'zone-rau-an-la': const [
      DemoTask(
        id: 'task-tuoi-rau',
        zoneId: 'zone-rau-an-la',
        title: 'Tưới nước luống',
        timeLabel: '06:00',
        status: DemoTaskStatus.done,
        assignee: 'Minh',
      ),
      DemoTask(
        id: 'task-bon-phan',
        zoneId: 'zone-rau-an-la',
        title: 'Bón phân bổ sung',
        timeLabel: '15:30',
        assignee: 'Minh',
      ),
      DemoTask(
        id: 'task-bat-san',
        zoneId: 'zone-rau-an-la',
        title: 'Bắt sâu ×kiểm tra lá',
        timeLabel: '17:00',
      ),
      DemoTask(
        id: 'task-qua-han',
        zoneId: 'zone-rau-an-la',
        title: 'Kiểm tra rệp luống 2',
        timeLabel: 'Quá hạn · hôm qua',
        overdue: true,
        assignee: 'Minh',
      ),
      // Historical occurrences so the D-14 health window reaches the
      // five-eligible minimum (done|skipped are in-denominator).
      DemoTask(
        id: 'task-rau-hom-qua',
        zoneId: 'zone-rau-an-la',
        title: 'Tưới sáng luống rau',
        timeLabel: 'Hôm qua · 06:10',
        status: DemoTaskStatus.done,
        assignee: 'Minh',
      ),
      DemoTask(
        id: 'task-rau-bo-qua',
        zoneId: 'zone-rau-an-la',
        title: 'Rải vôi bột luống',
        timeLabel: 'Hôm qua · 15:30',
        status: DemoTaskStatus.done,
      ),
    ],
    'zone-ca-chua': const [
      DemoTask(
        id: 'task-vuot-gian',
        zoneId: 'zone-ca-chua',
        title: 'Vượt giàn, buộc dây',
        timeLabel: '07:30',
        assignee: 'An',
      ),
      // Historical occurrences so the D-14 health window has ≥5 eligible
      // entries (done|skipped in-denominator; open/cancelled excluded).
      DemoTask(
        id: 'task-ca-chua-hom-qua',
        zoneId: 'zone-ca-chua',
        title: 'Kiểm tra giàn cà chua',
        timeLabel: 'Hôm qua · 07:00',
        status: DemoTaskStatus.done,
        assignee: 'An',
      ),
      DemoTask(
        id: 'task-ca-chua-bo-qua',
        zoneId: 'zone-ca-chua',
        title: 'Xịt phân lá',
        timeLabel: 'Hôm qua · 15:00',
        status: DemoTaskStatus.skipped,
      ),
    ],
    'zone-vuon-rau': const [
      DemoTask(
        id: 'task-lam-co',
        zoneId: 'zone-vuon-rau',
        title: 'Làm cỏ vườn',
        timeLabel: '16:00',
        status: DemoTaskStatus.done,
      ),
      DemoTask(
        id: 'task-vuon-tuoi-som',
        zoneId: 'zone-vuon-rau',
        title: 'Tưới sáng vườn rau',
        timeLabel: 'Hôm qua · 06:30',
        status: DemoTaskStatus.done,
      ),
    ],
  };

  const tankBonNuoc = DemoWaterTank(
    id: 'tank-bon-nuoc',
    zoneId: 'zone-bon-nuoc',
    name: 'Bồn nước 5000 lít',
    capacityLitres: '5000',
    storedLitres: '3200',
    usedTodayLitres: '450',
    source: 'đồng hồ đọc tay',
    asOf: '06:15',
  );

  const herdsBaVi = [
    DemoHerd(
      id: 'herd-bo',
      farmId: farmBaViId,
      category: DemoAnimalCategory.cows,
      species: 'Bò lai Sind',
      mode: DemoHerdMode.tracked,
    ),
    DemoHerd(
      id: 'herd-ga',
      farmId: farmBaViId,
      category: DemoAnimalCategory.chickens,
      species: 'Gà ri thả vườn',
      mode: DemoHerdMode.batch,
      batchQuantity: 120,
    ),
    DemoHerd(
      id: 'herd-cuu',
      farmId: farmBaViId,
      category: DemoAnimalCategory.sheep,
      species: 'Cừu Phan Rang',
      mode: DemoHerdMode.tracked,
    ),
  ];

  const animalsBaVi = [
    DemoAnimal(
      id: 'animal-bo-01',
      farmId: farmBaViId,
      herdId: 'herd-bo',
      tag: 'BO-01',
      name: 'Bò Mai',
      category: DemoAnimalCategory.cows,
      birthDate: '2023-08-12',
    ),
    DemoAnimal(
      id: 'animal-bo-02',
      farmId: farmBaViId,
      herdId: 'herd-bo',
      tag: 'BO-02',
      name: 'Bò Hồng',
      category: DemoAnimalCategory.cows,
      birthDate: '2024-07-03',
    ),
    // Sold record: stays visible, never counts toward headcount (D-05).
    DemoAnimal(
      id: 'animal-bo-03',
      farmId: farmBaViId,
      herdId: 'herd-bo',
      tag: 'BO-03',
      name: 'Bò Đen',
      category: DemoAnimalCategory.cows,
      birthDate: '2022-11-20',
      status: DemoAnimalStatus.sold,
    ),
    DemoAnimal(
      id: 'animal-cuu-01',
      farmId: farmBaViId,
      herdId: 'herd-cuu',
      tag: 'CUU-01',
      name: 'Cừu soma',
      category: DemoAnimalCategory.sheep,
      birthDate: '2025-08-01',
    ),
    // Deceased record: kept as history, excluded from headcount (D-05).
    DemoAnimal(
      id: 'animal-cuu-02',
      farmId: farmBaViId,
      herdId: 'herd-cuu',
      tag: 'CUU-02',
      name: 'Cừu bé',
      category: DemoAnimalCategory.sheep,
      status: DemoAnimalStatus.deceased,
    ),
  ];

  const feedingBaVi = [
    DemoFeedingEntry(
      id: 'feed-ga',
      timeLabel: '06:30',
      category: DemoAnimalCategory.chickens,
      feedLabel: 'Thóc trộn ngô',
      total: 4,
      done: 4,
    ),
    DemoFeedingEntry(
      id: 'feed-bo',
      timeLabel: '07:00',
      category: DemoAnimalCategory.cows,
      feedLabel: 'Cỏ tươi + rơm',
      total: 3,
      done: 2,
    ),
    DemoFeedingEntry(
      id: 'feed-cuu',
      timeLabel: '16:30',
      category: DemoAnimalCategory.sheep,
      feedLabel: 'Cỏ cắt nhỏ',
      total: 2,
      done: 0,
    ),
    DemoFeedingEntry(
      id: 'feed-de',
      timeLabel: '17:00',
      category: DemoAnimalCategory.goats,
      feedLabel: 'Cỏ + nước sạch',
      total: 2,
      done: 1,
    ),
  ];

  const harvestsBaVi = [
    DemoHarvestRecord(
      id: 'harvest-1',
      cropLabel: 'Cải ngọt',
      quantityKg: '12.5',
      harvestedOn: '2026-10-01',
      status: DemoHarvestStatus.confirmed,
    ),
    DemoHarvestRecord(
      id: 'harvest-2',
      cropLabel: 'Cải ngọt',
      quantityKg: '8.75',
      harvestedOn: '2026-10-02',
      status: DemoHarvestStatus.confirmed,
    ),
    DemoHarvestRecord(
      id: 'harvest-3',
      cropLabel: 'Mồng tây',
      quantityKg: '20.0',
      harvestedOn: '2026-10-03',
      status: DemoHarvestStatus.confirmed,
    ),
    DemoHarvestRecord(
      id: 'harvest-4',
      cropLabel: 'Cải ngọt',
      quantityKg: '5.25',
      harvestedOn: '2026-10-04',
      status: DemoHarvestStatus.confirmed,
    ),
    DemoHarvestRecord(
      id: 'harvest-5',
      cropLabel: 'Mồng tây',
      quantityKg: '15.0',
      harvestedOn: '2026-10-05',
      status: DemoHarvestStatus.confirmed,
    ),
    DemoHarvestRecord(
      id: 'harvest-6',
      cropLabel: 'Cải ngọt',
      quantityKg: '6.5',
      harvestedOn: '2026-10-06',
      status: DemoHarvestStatus.localPending,
    ),
  ];

  const harvestsTrongTai = [
    DemoHarvestRecord(
      id: 'harvest-tt-1',
      cropLabel: 'Mồng tây',
      quantityKg: '3.0',
      harvestedOn: '2026-10-04',
      status: DemoHarvestStatus.confirmed,
    ),
  ];

  final syncItems = const [
    DemoSyncItem(
      id: 'sync-conflict-1',
      farmId: farmBaViId,
      operationType: 'harvest.create',
      status: DemoSyncStatus.conflict,
      localSummary: 'Cải ngọt: 12.5 kg ngày 2026-10-01 (bản của bạn)',
      serverSummary: 'Cải ngọt: 12.0 kg ngày 2026-10-01 (đã có trên máy chủ)',
      baseVersion: 3,
      updatedLabel: 'Đụng độ khi đồng bộ',
      asOfLabel: 'Máy chủ cập nhật 06:12',
    ),
    DemoSyncItem(
      id: 'sync-pending-1',
      farmId: farmBaViId,
      operationType: 'harvest.create',
      status: DemoSyncStatus.localPending,
      localSummary: 'Cải ngọt: 6.5 kg ngày 2026-10-06',
      updatedLabel: 'Chờ mạng',
    ),
  ];

  const notifications = [
    DemoNotification(
      id: 'notif-1',
      title: 'Nhiệm vụ hôm nay',
      body: 'Còn 3 việc chưa xong ở Nông trại Ba Vì.',
      timeLabel: '06:00',
    ),
    DemoNotification(
      id: 'notif-2',
      title: 'Có bản ghi cần kiểm tra',
      body: 'Một bản ghi thu hoạch đang xung đột với máy chủ.',
      timeLabel: 'Hôm qua',
    ),
  ];

  return DemoDataState(
    organizations: organizations,
    farms: farms,
    zonesByFarm: {
      farmBaViId: zonesBaVi,
      _farmTrongTaiId: zonesTrongTai,
      farmMoiId: const [],
    },
    cropsByFarm: {
      farmBaViId: cropsBaVi,
      _farmTrongTaiId: cropsTrongTai,
      farmMoiId: const [],
    },
    tasksByZone: tasksByZone,
    tanksByZone: {'zone-bon-nuoc': const [tankBonNuoc]},
    herdsByFarm: {
      farmBaViId: herdsBaVi,
      _farmTrongTaiId: const [],
      farmMoiId: const [],
    },
    animalsByFarm: {
      farmBaViId: animalsBaVi,
      _farmTrongTaiId: const [],
      farmMoiId: const [],
    },
    feedingByFarm: {
      farmBaViId: feedingBaVi,
      _farmTrongTaiId: const [],
      farmMoiId: const [],
    },
    harvestsByFarm: {
      farmBaViId: harvestsBaVi,
      _farmTrongTaiId: harvestsTrongTai,
      farmMoiId: const [],
    },
    moistureByZone: const {
      'zone-rau-an-la': [
        DemoMoistureReading(
          id: 'moisture-seed-1',
          zoneId: 'zone-rau-an-la',
          valuePercent: '41.5',
          method: 'đo tay',
          source: 'đồng hồ đọc tay',
          asOf: 'hôm qua 17:20',
        ),
      ],
    },
    waterUsageByTank: const {
      'tank-bon-nuoc': [
        DemoWaterUsage(
          id: 'usage-seed-1',
          tankId: 'tank-bon-nuoc',
          litres: '450',
          usedOn: 'hôm nay',
          purpose: 'Tưới luống rau',
        ),
      ],
    },
    weatherByFarm: const {
      farmBaViId: DemoWeatherSnapshot(
        farmId: farmBaViId,
        provider: 'Open-Meteo (bộ nhớ đệm demo)',
        temperatureC: '26.8',
        conditionLabel: 'Nhiều mây',
        humidityPercent: '78',
        windLabel: 'Gió nhẹ',
        validAt: '07:00',
        fetchedAt: '06:45',
        status: DemoWeatherStatus.fresh,
      ),
    },
    productionByHerd: const {
      'herd-ga': [
        DemoProductionRecord(
          id: 'prod-seed-1',
          herdId: 'herd-ga',
          product: 'eggs',
          quantity: '86',
          unit: 'quả',
          recordedOn: 'hôm qua',
        ),
      ],
      'herd-bo': [
        DemoProductionRecord(
          id: 'prod-seed-2',
          herdId: 'herd-bo',
          product: 'milk',
          quantity: '12.5',
          unit: 'lít',
          recordedOn: 'hôm nay 05:40',
        ),
      ],
    },
    syncItems: syncItems,
    notifications: notifications,
    selectedOrganizationId: _orgHtxId,
    selectedFarmId: farmBaViId,
  );
}
