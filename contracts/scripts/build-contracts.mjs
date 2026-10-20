import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const OPENAPI_PATH = 'contracts/openapi/farmly-v1.yaml';
const DART_PATH = 'apps/mobile/lib/generated/farmly_api_types.dart';

const ref = (name) => ({ $ref: `#/components/schemas/${name}` });
const str = (extra = {}) => ({ type: 'string', ...extra });
const int = (extra = {}) => ({ type: 'integer', format: 'int32', ...extra });
const object = (properties, required = [], extra = {}) => ({
  type: 'object',
  properties,
  required,
  additionalProperties: false,
  ...extra,
});
const array = (items, extra = {}) => ({ type: 'array', items, ...extra });

export const bootstrapEntities = [
  'farm',
  'zones',
  'cropSpecies',
  'plantings',
  'plantingEvents',
  'herds',
  'animals',
  'livestockMovements',
  'animalObservations',
  'productionRecords',
  'taskTemplates',
  'taskOccurrences',
  'taskTransitions',
  'harvestRecords',
  'harvestHeads',
  'correctionProposals',
  'moistureReadings',
  'waterTanks',
  'waterReadings',
  'waterUsages',
];

const mutationTypes = [
  'farm.create', 'farm.update', 'farm.archive',
  'zone.create', 'zone.update', 'zone.archive',
  'cropSpecies.create', 'cropSpecies.update', 'cropSpecies.archive',
  'planting.create', 'planting.update', 'planting.archive', 'plantingEvent.create',
  'herd.create', 'herd.update', 'herd.archive', 'animal.create', 'animal.update', 'animal.archive',
  'livestockMovement.create', 'animalObservation.create', 'productionRecord.create',
  'taskTemplate.create', 'taskTemplate.update', 'taskOccurrence.transition',
  'harvest.create', 'harvest.correction.propose', 'harvest.correction.apply', 'harvest.void',
  'moistureReading.create', 'waterTank.create', 'waterTank.update', 'waterTank.archive',
  'waterReading.create', 'waterUsage.create', 'irrigationTask.transition',
];

const aiEventTypes = [
  'request.started',
  'response.delta',
  'request.status',
  'response.references',
  'usage.reported',
  'response.completed',
  'response.cancelled',
  'response.error',
];

// Strict P05 farm-scoped mutation envelope: farm-mutation.v1 fields with a const
// `type` and a strict per-type `payload`. Creates may send `baseVersion` only as
// null (or omit it); updates and archives require the CAS version. Approved by
// the P05 contract decision (reports/p05-api-contract-decision-2026-10-08.md).
const farmScopedMutation = (typeConst, payloadSchema, baseVersionMode) => {
  const baseVersion = baseVersionMode === 'required'
    ? int({ minimum: 1 })
    : { type: 'null', description: 'Create mutations omit the compare-and-swap version; send null or omit the field.' };
  const required = ['schemaVersion', 'continuityEpoch', 'operationId', 'type', 'resourceId'];
  if (baseVersionMode === 'required') required.push('baseVersion');
  required.push('dependsOn', 'payload');
  return object({
    schemaVersion: str({ const: 'farm-mutation.v1' }),
    continuityEpoch: str({ minLength: 1 }),
    operationId: ref('Uuid'),
    type: str({ const: typeConst }),
    resourceId: ref('Uuid'),
    baseVersion,
    dependsOn: array(ref('Uuid'), { maxItems: 50 }),
    payload: payloadSchema,
  }, required);
};

const schemas = {
  DecimalString: str({
    format: 'decimal-string',
    pattern: '^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?$',
    description: 'Canonical base-10 value encoded as a JSON string; never a JSON number.',
    examples: ['12.375', '125000.00'],
  }),
  PolicyVersion: str({
    format: 'positive-decimal-string',
    pattern: '^[1-9][0-9]*$',
    description: 'Positive PostgreSQL BIGINT encoded as exact decimal JSON text; never convert through a JSON number.',
  }),
  CivilDate: str({ format: 'date', pattern: '^\\d{4}-\\d{2}-\\d{2}$' }),
  UtcInstant: str({ format: 'date-time', description: 'UTC RFC3339 instant ending in Z.' }),
  Uuid: str({ format: 'uuid' }),
  FarmlyErrorCode: str({
    enum: [
      'UNAUTHENTICATED', 'ACCESS_REVOKED', 'PERMISSION_DENIED', 'NOT_FOUND',
      'VALIDATION_FAILED', 'VERSION_CONFLICT', 'OPERATION_ID_REUSED',
      'IDEMPOTENCY_IN_PROGRESS', 'CURSOR_EXPIRED', 'RECONCILIATION_REQUIRED',
      'BOOTSTRAP_TOO_LARGE', 'UPGRADE_REQUIRED', 'AI_QUOTA_EXCEEDED',
      'UPSTREAM_UNAVAILABLE', 'RATE_LIMITED',
      'INVITATION_NOT_AVAILABLE', 'INVITATION_EMAIL_MISMATCH',
      'INVITATION_EXPIRED', 'INVITATION_REVOKED',
      'INVITATION_ALREADY_ACCEPTED', 'MEMBERSHIP_ALREADY_EXISTS',
      'INTERNAL_ERROR',
    ],
  }),
  FieldError: object({
    code: str(),
    message: str(),
  }, ['code', 'message']),
  ApiError: object({
    code: ref('FarmlyErrorCode'),
    message: str(),
    fieldErrors: { type: 'array', items: ref('FieldError') },
    retryable: { type: 'boolean' },
    requestId: ref('Uuid'),
  }, ['code', 'message', 'retryable', 'requestId']),
  ErrorEnvelope: object({ error: ref('ApiError') }, ['error']),
  ResponseMeta: object({
    schemaVersion: str(),
    asOf: ref('UtcInstant'),
    scopePolicyVersion: ref('PolicyVersion'),
  }, ['schemaVersion', 'asOf']),
  PageInfo: object({
    nextCursor: str(),
    hasMore: { type: 'boolean' },
  }, ['hasMore']),
  OrganizationMembershipListMeta: object({
    schemaVersion: str(),
    asOf: ref('UtcInstant'),
    scopePolicyVersion: ref('PolicyVersion'),
  }, ['schemaVersion', 'asOf', 'scopePolicyVersion']),
  SuccessEnvelope: object({
    data: { type: 'object', additionalProperties: true },
    page: ref('PageInfo'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  FarmScope: object({
    organizationId: ref('Uuid'),
    farmId: ref('Uuid'),
    continuityEpoch: str({ minLength: 1 }),
    scopePolicyVersion: ref('PolicyVersion'),
  }, ['organizationId', 'farmId', 'continuityEpoch', 'scopePolicyVersion']),
  FarmDirectoryEntry: object({
    farmId: ref('Uuid'),
    farmName: str({ minLength: 1, maxLength: 160 }),
    status: str({ enum: ['active', 'archived'] }),
    grantRole: str({ enum: ['owner', 'admin', 'manager', 'worker', 'viewer'] }),
  }, ['farmId', 'farmName', 'status', 'grantRole']),
  FarmDirectoryManifest: object({
    schemaVersion: str({ const: 'farm-directory.v1' }),
    scopePolicyVersion: ref('PolicyVersion'),
    continuityEpoch: str({ minLength: 1 }),
    farms: array(ref('FarmDirectoryEntry')),
    nextCursor: str({ minLength: 1, maxLength: 2048, description: 'Signed opaque cursor pinned to organization, actor, policy version, continuity epoch, last farm UUID, and page size.' }),
  }, ['schemaVersion', 'scopePolicyVersion', 'continuityEpoch', 'farms']),
  FarmMutation: object({
    schemaVersion: str({ const: 'farm-mutation.v1' }),
    continuityEpoch: str({ minLength: 1 }),
    operationId: ref('Uuid'),
    type: str({ enum: mutationTypes }),
    resourceId: ref('Uuid'),
    baseVersion: { type: ['integer', 'null'], minimum: 1 },
    dependsOn: array(ref('Uuid'), { maxItems: 50 }),
    payload: { type: 'object', additionalProperties: true },
  }, ['schemaVersion', 'continuityEpoch', 'operationId', 'type', 'resourceId', 'dependsOn', 'payload']),
  FarmMutationBatch: object({
    schemaVersion: str({ const: 'farm-mutation-batch.v1' }),
    continuityEpoch: str({ minLength: 1 }),
    operations: array(ref('FarmMutation'), { minItems: 1, maxItems: 50 }),
  }, ['schemaVersion', 'continuityEpoch', 'operations']),
  FarmMutationOutcome: object({
    operationId: ref('Uuid'),
    outcome: str({ enum: ['applied', 'rejected', 'conflict', 'unknown'] }),
    code: ref('FarmlyErrorCode'),
  }, ['operationId', 'outcome']),
  MutationBatchResult: object({
    schemaVersion: str(),
    outcomes: array(ref('FarmMutationOutcome'), { minItems: 1, maxItems: 50 }),
  }, ['schemaVersion', 'outcomes']),
  OperationStatus: object({
    operationId: ref('Uuid'),
    outcome: str({ enum: ['applied', 'rejected', 'unknown'] }),
  }, ['operationId', 'outcome']),
  BootstrapChunkDescriptor: object({
    chunkId: str(),
    entity: str(),
    rowOffset: int({ minimum: 0 }),
    rowCount: int({ minimum: 0 }),
    sha256: str({ pattern: '^[a-f0-9]{64}$' }),
  }, ['chunkId', 'entity', 'rowOffset', 'rowCount', 'sha256']),
  BootstrapManifest: object({
    schemaVersion: str({ const: 'farm-bootstrap-manifest.v1' }),
    snapshotId: ref('Uuid'),
    scope: ref('FarmScope'),
    highWatermark: str({ pattern: '^(0|[1-9][0-9]*)$' }),
    createdAt: ref('UtcInstant'),
    expiresAt: ref('UtcInstant'),
    chunks: array(ref('BootstrapChunkDescriptor')),
  }, ['schemaVersion', 'snapshotId', 'scope', 'highWatermark', 'createdAt', 'expiresAt', 'chunks']),
  BootstrapChunk: object({
    schemaVersion: str({ const: 'farm-bootstrap-chunk.v1' }),
    snapshotId: ref('Uuid'),
    chunkId: str(),
    entity: str(),
    rowOffset: int({ minimum: 0 }),
    rows: array({ type: 'object', additionalProperties: true }),
    nextCursor: str(),
  }, ['schemaVersion', 'snapshotId', 'chunkId', 'entity', 'rowOffset', 'rows']),
  DomainCommandRequest: object({
    operationId: ref('Uuid'),
    payload: { type: 'object', additionalProperties: true },
  }, ['operationId', 'payload']),
  CreateOrganizationRequest: object({
    operationId: ref('Uuid'),
    name: str({ minLength: 1, maxLength: 120 }),
  }, ['operationId', 'name']),
  InvitationFarmGrantRequest: object({
    farmId: ref('Uuid'),
    role: str({ enum: ['manager', 'worker', 'viewer'] }),
  }, ['farmId', 'role']),
  CreateOrganizationInvitationPayload: object({
    email: str({ format: 'email', maxLength: 320 }),
    role: str({ enum: ['admin', 'member', 'viewer'] }),
    farmGrants: array(ref('InvitationFarmGrantRequest'), { maxItems: 100, default: [] }),
  }, ['email', 'role']),
  CreateOrganizationInvitationRequest: object({
    operationId: ref('Uuid'),
    payload: ref('CreateOrganizationInvitationPayload'),
  }, ['operationId', 'payload']),
  AcceptOrganizationInvitationPayload: object({
    token: str({ pattern: '^[a-f0-9]{64}$', description: 'The 256-bit invitation token supplied to the invitee.' }),
  }, ['token']),
  AcceptOrganizationInvitationRequest: object({
    operationId: ref('Uuid'),
    payload: ref('AcceptOrganizationInvitationPayload'),
  }, ['operationId', 'payload']),
  OrganizationInvitationView: object({
    id: ref('Uuid'),
    role: str({ enum: ['admin', 'member', 'viewer'] }),
    status: str({ enum: ['pending', 'accepted', 'expired', 'revoked'] }),
    createdAt: ref('UtcInstant'),
    expiresAt: ref('UtcInstant'),
    acceptedAt: { type: ['string', 'null'], format: 'date-time' },
    revokedAt: { type: ['string', 'null'], format: 'date-time' },
  }, ['id', 'role', 'status', 'createdAt', 'expiresAt', 'acceptedAt', 'revokedAt']),
  OrganizationInvitationListData: object({
    invitations: array(ref('OrganizationInvitationView')),
  }, ['invitations']),
  OrganizationInvitationListResponse: object({
    data: ref('OrganizationInvitationListData'),
    page: ref('PageInfo'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  OrganizationMembershipFarmGrant: object({
    farmId: ref('Uuid'),
    role: str({ enum: ['manager', 'worker', 'viewer'] }),
    version: int({ minimum: 1 }),
  }, ['farmId', 'role', 'version']),
  OrganizationMembershipView: object({
    id: ref('Uuid'),
    userId: str(),
    role: str({ enum: ['owner', 'admin', 'member', 'viewer'] }),
    status: str({ enum: ['active', 'suspended', 'removed'] }),
    version: int({ minimum: 1 }),
    farmGrants: array(ref('OrganizationMembershipFarmGrant')),
  }, ['id', 'userId', 'role', 'status', 'version', 'farmGrants']),
  OrganizationMembershipListData: object({
    memberships: array(ref('OrganizationMembershipView')),
  }, ['memberships']),
  OrganizationMembershipListResponse: object({
    data: ref('OrganizationMembershipListData'),
    page: ref('PageInfo'),
    meta: ref('OrganizationMembershipListMeta'),
  }, ['data', 'meta']),
  PatchOrganizationMembershipPayload: object({
    role: str({ enum: ['admin', 'member', 'viewer'] }),
    farmGrants: array(ref('InvitationFarmGrantRequest'), { maxItems: 100 }),
  }, ['role', 'farmGrants']),
  PatchOrganizationMembershipRequest: object({
    operationId: ref('Uuid'),
    payload: ref('PatchOrganizationMembershipPayload'),
  }, ['operationId', 'payload']),
  OrganizationMembershipMutationData: object({
    membership: ref('OrganizationMembershipView'),
    policyVersion: str({ pattern: '^[1-9][0-9]*$' }),
    changed: { type: 'boolean' },
    replayed: { type: 'boolean' },
  }, ['membership', 'policyVersion', 'changed', 'replayed']),
  OrganizationMembershipMutationResponse: object({
    data: ref('OrganizationMembershipMutationData'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  TransferOrganizationOwnershipPayload: object({
    targetMembershipId: ref('Uuid'),
    removeFormerOwner: { type: 'boolean', default: false },
  }, ['targetMembershipId']),
  TransferOrganizationOwnershipRequest: object({
    operationId: ref('Uuid'),
    payload: ref('TransferOrganizationOwnershipPayload'),
  }, ['operationId', 'payload']),
  OwnershipTransferData: object({
    targetMembershipId: ref('Uuid'),
    formerOwnerMembershipId: ref('Uuid'),
    formerOwnerRole: str({ enum: ['admin', 'owner'] }),
    formerOwnerStatus: str({ enum: ['active', 'removed'] }),
    policyVersion: str({ pattern: '^[1-9][0-9]*$' }),
    replayed: { type: 'boolean' },
  }, ['targetMembershipId', 'formerOwnerMembershipId', 'formerOwnerRole', 'formerOwnerStatus', 'policyVersion', 'replayed']),
  OwnershipTransferResponse: object({
    data: ref('OwnershipTransferData'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  CreatedOrganizationInvitationData: object({
    invitation: object({
      id: ref('Uuid'),
      role: str({ enum: ['admin', 'member', 'viewer'] }),
      status: str({ const: 'pending' }),
      createdAt: ref('UtcInstant'),
      expiresAt: ref('UtcInstant'),
    }, ['id', 'role', 'status', 'createdAt', 'expiresAt']),
    acceptanceToken: str({
      pattern: '^[a-f0-9]{64}$',
      description: 'Returned once to the authorized creator for delivery over an approved channel; never stored in plaintext.',
    }),
  }, ['invitation', 'acceptanceToken']),
  CreatedOrganizationInvitationResponse: object({
    data: ref('CreatedOrganizationInvitationData'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  AcceptedOrganizationInvitationData: object({
    organizationId: ref('Uuid'),
    membership: object({
      id: ref('Uuid'),
      role: str({ enum: ['admin', 'member', 'viewer'] }),
      status: str({ const: 'active' }),
      version: int({ minimum: 1 }),
    }, ['id', 'role', 'status', 'version']),
    policyVersion: str({ pattern: '^[1-9][0-9]*$' }),
    replayed: { type: 'boolean' },
  }, ['organizationId', 'membership', 'policyVersion', 'replayed']),
  AcceptedOrganizationInvitationResponse: object({
    data: ref('AcceptedOrganizationInvitationData'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  RevokeOrganizationInvitationRequest: object({
    operationId: ref('Uuid'),
  }, ['operationId']),
  RevokedOrganizationInvitationData: object({
    invitation: object({
      id: ref('Uuid'),
      status: str({ const: 'revoked' }),
      revokedAt: ref('UtcInstant'),
    }, ['id', 'status', 'revokedAt']),
    policyVersion: str({ pattern: '^[1-9][0-9]*$' }),
    replayed: { type: 'boolean' },
  }, ['invitation', 'policyVersion', 'replayed']),
  RevokedOrganizationInvitationResponse: object({
    data: ref('RevokedOrganizationInvitationData'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  TaskTransitionRequest: object({
    operationId: ref('Uuid'),
    expectedVersion: int({ minimum: 1 }),
    transition: str({ enum: ['complete', 'skip', 'reopen', 'cancel'] }),
    reason: str({ maxLength: 500 }),
  }, ['operationId', 'expectedVersion', 'transition']),
  AiCreateRequest: object({
    schemaVersion: str({ const: 'farmly-ai-request.v1' }),
    clientRequestId: ref('Uuid'),
    conversationId: ref('Uuid'),
    prompt: str({ minLength: 1, maxLength: 12000 }),
    consentRevision: int({ minimum: 1 }),
    contextMode: str({ enum: ['authorized-summary', 'none'] }),
  }, ['schemaVersion', 'clientRequestId', 'prompt', 'consentRevision', 'contextMode']),
  AiCancelRequest: object({
    reason: str({ maxLength: 200 }),
  }),
  AiRequestStatus: object({
    requestId: ref('Uuid'),
    status: str({ enum: ['queued', 'generating', 'stopping', 'completed', 'cancelled', 'interrupted', 'error'] }),
    latestSeq: int({ minimum: 0 }),
    usageState: str({ enum: ['reserved', 'reported', 'estimated', 'unknown'] }),
    finalMessageId: ref('Uuid'),
  }, ['requestId', 'status', 'latestSeq', 'usageState']),
  AiSourceReference: object({
    sourceId: str(),
    coverage: str(),
    asOf: ref('UtcInstant'),
  }, ['sourceId', 'coverage', 'asOf']),
  AiRequestStartedData: object({
    requestId: ref('Uuid'),
    conversationId: ref('Uuid'),
    snapshotId: ref('Uuid'),
    asOf: ref('UtcInstant'),
    modelAlias: str(),
    schemaVersion: str(),
  }, ['requestId', 'conversationId', 'asOf', 'modelAlias', 'schemaVersion']),
  AiResponseDeltaData: object({
    seq: int({ minimum: 1 }),
    textDelta: str({ maxLength: 8192 }),
  }, ['seq', 'textDelta']),
  AiRequestStatusData: object({
    status: str({ enum: ['queued', 'generating', 'stopping', 'interrupted'] }),
  }, ['status']),
  AiResponseReferencesData: object({
    references: array(ref('AiSourceReference'), { maxItems: 100 }),
  }, ['references']),
  AiUsageReportedData: object({
    usageState: str({ enum: ['reported', 'estimated', 'unknown'] }),
    inputTokens: int({ minimum: 0 }),
    outputTokens: int({ minimum: 0 }),
    totalTokens: int({ minimum: 0 }),
  }, ['usageState']),
  AiResponseCompletedData: object({
    finalMessageId: ref('Uuid'),
    finishReason: str({ enum: ['stop', 'length'] }),
    truncated: { type: 'boolean' },
    usageState: str({ enum: ['reported', 'estimated', 'unknown'] }),
  }, ['finalMessageId', 'finishReason', 'usageState']),
  AiResponseCancelledData: object({
    partial: { type: 'boolean' },
    usageState: str({ enum: ['reported', 'estimated', 'unknown'] }),
  }, ['usageState']),
  AiResponseErrorData: object({
    code: ref('FarmlyErrorCode'),
    retryable: { type: 'boolean' },
    statusUrl: str({ format: 'uri-reference' }),
  }, ['code', 'retryable']),
  AiEvent: object({
    id: str({ pattern: '^.+:[1-9][0-9]*$' }),
    requestId: ref('Uuid'),
    seq: int({ minimum: 1 }),
    type: str({ enum: aiEventTypes }),
    data: { type: 'object', additionalProperties: true },
  }, ['id', 'requestId', 'seq', 'type', 'data']),
  DeviceRegistrationRequest: object({
    operationId: ref('Uuid'),
    action: str({ enum: ['register', 'revoke'] }),
    deviceId: str({ minLength: 1, maxLength: 200 }),
    pushToken: str({ writeOnly: true, maxLength: 4096 }),
  }, ['operationId', 'action', 'deviceId']),
  PrivacyRequest: object({
    operationId: ref('Uuid'),
    action: str({ enum: ['export', 'delete-history', 'withdraw-ai-consent'] }),
    confirmation: str({ maxLength: 120 }),
  }, ['operationId', 'action']),
  AiConsentDecision: object({
    granted: { type: 'boolean' },
    aiSafeSummaryOptedIn: { type: 'boolean' },
  }, ['granted']),
  WaterTankDto: object({
    id: ref('Uuid'),
    version: int({ minimum: 1 }),
    name: str(),
    zoneId: ref('Uuid'),
    capacityLitres: ref('DecimalString'),
    storedLitres: ref('DecimalString'),
    status: str({ enum: ['active', 'archived'] }),
  }, ['id', 'version', 'name', 'zoneId', 'capacityLitres', 'status']),
  HarvestDto: object({
    id: ref('Uuid'),
    version: int({ minimum: 1 }),
    quantityKg: ref('DecimalString'),
    harvestDate: ref('CivilDate'),
    occurredAt: ref('UtcInstant'),
  }, ['id', 'version', 'quantityKg', 'harvestDate', 'occurredAt']),
  AreaM2String: str({
    format: 'decimal-string',
    pattern: '^(0|[1-9][0-9]{0,11})(\\.[0-9]{1,2})?$',
    description: 'Canonical non-negative base-10 area in square metres fitting PostgreSQL NUMERIC(14,2); encoded as a JSON string.',
  }),
  UnitInterval: str({
    format: 'decimal-string',
    pattern: '^(0(\\.[0-9]+)?|1(\\.0+)?)$',
    description: 'Canonical base-10 scene coordinate in the closed interval [0,1]; encoded as a JSON string.',
  }),
  ZonePoint: object({
    x: ref('UnitInterval'),
    y: ref('UnitInterval'),
  }, ['x', 'y']),
  ZoneGeometry: object({
    points: array(ref('ZonePoint'), {
      minItems: 3,
      maxItems: 128,
      description: 'Scene-local normalized polygon with no geographic coordinates.',
    }),
  }, ['points']),
  EmptyMutationPayload: object({}, []),
  // Coarse weather grid "lat,lon" — exactly one decimal digit per axis
  // (0.1 degree ≈ 5–11 km) so an exact coordinate is unrepresentable on the
  // wire (P-05). `null` on update clears the farm's weather location.
  CoarseWeatherGrid: {
    anyOf: [
      str({ pattern: '^-?[0-9]{1,2}\\.[0-9],-?[0-9]{1,3}\\.[0-9]$' }),
      { type: 'null' },
    ],
    description: 'Coarse grid reference "lat,lon" rounded to 0.1 degree; null clears it.',
  },
  FarmCreatePayload: object({
    name: str({ minLength: 1, maxLength: 160 }),
    timezone: str({ minLength: 1, maxLength: 64, description: 'IANA timezone name for farm-local civil dates.' }),
    areaM2: ref('AreaM2String'),
    location: ref('CoarseWeatherGrid'),
  }, ['name', 'timezone']),
  FarmUpdatePayload: object({
    name: str({ minLength: 1, maxLength: 160 }),
    timezone: str({ minLength: 1, maxLength: 64 }),
    areaM2: ref('AreaM2String'),
    location: ref('CoarseWeatherGrid'),
  }, [], { minProperties: 1 }),
  ZoneCreatePayload: object({
    name: str({ minLength: 1, maxLength: 160 }),
    type: str({ enum: ['house', 'crop_plot', 'livestock_area', 'water', 'storage', 'other'] }),
    geometry: ref('ZoneGeometry'),
    areaM2: ref('AreaM2String'),
  }, ['name', 'type', 'geometry']),
  ZoneUpdatePayload: object({
    name: str({ minLength: 1, maxLength: 160 }),
    type: str({ enum: ['house', 'crop_plot', 'livestock_area', 'water', 'storage', 'other'] }),
    geometry: ref('ZoneGeometry'),
    areaM2: ref('AreaM2String'),
  }, [], { minProperties: 1 }),
  CropSpeciesCreatePayload: object({
    name: str({ minLength: 1, maxLength: 160 }),
    harvestUnit: str({ enum: ['kg', 'litre', 'pieces'] }),
  }, ['name', 'harvestUnit']),
  CropSpeciesUpdatePayload: object({
    name: str({ minLength: 1, maxLength: 160 }),
    harvestUnit: str({ enum: ['kg', 'litre', 'pieces'] }),
  }, [], { minProperties: 1 }),
  PlantingCreatePayload: object({
    cropSpeciesId: ref('Uuid'),
    plotId: ref('Uuid'),
    status: str({ enum: ['planned', 'active', 'harvested', 'completed', 'archived'] }),
    sowingDate: ref('CivilDate'),
    expectedHarvestDate: ref('CivilDate'),
    areaM2: ref('AreaM2String'),
  }, ['cropSpeciesId', 'plotId', 'sowingDate']),
  PlantingUpdatePayload: object({
    status: str({ enum: ['planned', 'active', 'harvested', 'completed', 'archived'] }),
    sowingDate: ref('CivilDate'),
    expectedHarvestDate: ref('CivilDate'),
    areaM2: ref('AreaM2String'),
  }, [], { minProperties: 1 }),
  HerdCreatePayload: object({
    mode: str({ enum: ['batch', 'tracked'] }),
    status: str({ enum: ['active', 'archived'] }),
    species: str({ minLength: 1, maxLength: 120 }),
  }, ['mode']),
  HerdUpdatePayload: object({
    mode: str({ enum: ['batch', 'tracked'] }),
    status: str({ enum: ['active', 'archived'] }),
    species: str({ minLength: 1, maxLength: 120 }),
  }, [], { minProperties: 1 }),
  AnimalCreatePayload: object({
    herdId: ref('Uuid'),
    tag: str({ minLength: 1, maxLength: 64 }),
    name: str({ minLength: 1, maxLength: 160 }),
    birthDate: ref('CivilDate'),
    status: str({ enum: ['alive', 'sold', 'deceased'] }),
  }, ['herdId', 'tag']),
  AnimalUpdatePayload: object({
    tag: str({ minLength: 1, maxLength: 64 }),
    name: str({ minLength: 1, maxLength: 160 }),
    birthDate: ref('CivilDate'),
    status: str({ enum: ['alive', 'sold', 'deceased'] }),
  }, [], { minProperties: 1 }),
  WaterTankCreatePayload: object({
    name: str({ minLength: 1, maxLength: 160 }),
    zoneId: ref('Uuid'),
    capacityLitres: ref('DecimalString'),
  }, ['name', 'zoneId', 'capacityLitres']),
  WaterTankUpdatePayload: object({
    name: str({ minLength: 1, maxLength: 160 }),
    capacityLitres: ref('DecimalString'),
  }, [], { minProperties: 1 }),
  FarmCreateMutation: farmScopedMutation('farm.create', ref('FarmCreatePayload'), 'nullOnly'),
  FarmUpdateMutation: farmScopedMutation('farm.update', ref('FarmUpdatePayload'), 'required'),
  FarmArchiveMutation: farmScopedMutation('farm.archive', ref('EmptyMutationPayload'), 'required'),
  ZoneCreateMutation: farmScopedMutation('zone.create', ref('ZoneCreatePayload'), 'nullOnly'),
  ZoneUpdateMutation: farmScopedMutation('zone.update', ref('ZoneUpdatePayload'), 'required'),
  ZoneArchiveMutation: farmScopedMutation('zone.archive', ref('EmptyMutationPayload'), 'required'),
  CropSpeciesCreateMutation: farmScopedMutation('cropSpecies.create', ref('CropSpeciesCreatePayload'), 'nullOnly'),
  CropSpeciesUpdateMutation: farmScopedMutation('cropSpecies.update', ref('CropSpeciesUpdatePayload'), 'required'),
  CropSpeciesArchiveMutation: farmScopedMutation('cropSpecies.archive', ref('EmptyMutationPayload'), 'required'),
  PlantingCreateMutation: farmScopedMutation('planting.create', ref('PlantingCreatePayload'), 'nullOnly'),
  PlantingUpdateMutation: farmScopedMutation('planting.update', ref('PlantingUpdatePayload'), 'required'),
  PlantingArchiveMutation: farmScopedMutation('planting.archive', ref('EmptyMutationPayload'), 'required'),
  HerdCreateMutation: farmScopedMutation('herd.create', ref('HerdCreatePayload'), 'nullOnly'),
  HerdUpdateMutation: farmScopedMutation('herd.update', ref('HerdUpdatePayload'), 'required'),
  HerdArchiveMutation: farmScopedMutation('herd.archive', ref('EmptyMutationPayload'), 'required'),
  AnimalCreateMutation: farmScopedMutation('animal.create', ref('AnimalCreatePayload'), 'nullOnly'),
  AnimalUpdateMutation: farmScopedMutation('animal.update', ref('AnimalUpdatePayload'), 'required'),
  AnimalArchiveMutation: farmScopedMutation('animal.archive', ref('EmptyMutationPayload'), 'required'),
  WaterTankCreateMutation: farmScopedMutation('waterTank.create', ref('WaterTankCreatePayload'), 'nullOnly'),
  WaterTankUpdateMutation: farmScopedMutation('waterTank.update', ref('WaterTankUpdatePayload'), 'required'),
  FarmDto: object({
    farmId: ref('Uuid'),
    name: str({ minLength: 1, maxLength: 160 }),
    areaM2: ref('AreaM2String'),
    timezone: str({ minLength: 1, maxLength: 64 }),
    location: ref('CoarseWeatherGrid'),
    status: str({ enum: ['active', 'archived'] }),
    version: int({ minimum: 1 }),
  }, ['farmId', 'name', 'timezone', 'status', 'version']),
  ZoneDto: object({
    id: ref('Uuid'),
    version: int({ minimum: 1 }),
    type: str({ enum: ['house', 'crop_plot', 'livestock_area', 'water', 'storage', 'other'] }),
    name: str({ minLength: 1, maxLength: 160 }),
    geometry: ref('ZoneGeometry'),
    areaM2: ref('AreaM2String'),
    status: str({ enum: ['active', 'archived'] }),
  }, ['id', 'version', 'type', 'name', 'geometry', 'status']),
  CropSpeciesDto: object({
    id: ref('Uuid'),
    version: int({ minimum: 1 }),
    name: str({ minLength: 1, maxLength: 160 }),
    harvestUnit: str({ enum: ['kg', 'litre', 'pieces'] }),
    status: str({ enum: ['active', 'archived'] }),
  }, ['id', 'version', 'name', 'harvestUnit', 'status']),
  PlantingDto: object({
    id: ref('Uuid'),
    version: int({ minimum: 1 }),
    cropSpeciesId: ref('Uuid'),
    plotId: ref('Uuid'),
    status: str({ enum: ['planned', 'active', 'harvested', 'completed', 'archived'] }),
    sowingDate: ref('CivilDate'),
    expectedHarvestDate: ref('CivilDate'),
    areaM2: ref('AreaM2String'),
  }, ['id', 'version', 'cropSpeciesId', 'plotId', 'status', 'sowingDate']),
  HerdDto: object({
    id: ref('Uuid'),
    version: int({ minimum: 1 }),
    mode: str({ enum: ['batch', 'tracked'] }),
    species: str({ minLength: 1, maxLength: 120 }),
    status: str({ enum: ['active', 'archived'] }),
    headcount: int({ minimum: 0 }),
  }, ['id', 'version', 'mode', 'status', 'headcount']),
  AnimalDto: object({
    id: ref('Uuid'),
    version: int({ minimum: 1 }),
    herdId: ref('Uuid'),
    tag: str({ minLength: 1, maxLength: 64 }),
    name: str({ minLength: 1, maxLength: 160 }),
    birthDate: ref('CivilDate'),
    status: str({ enum: ['alive', 'sold', 'deceased'] }),
    archived: { type: 'boolean' },
  }, ['id', 'version', 'herdId', 'tag', 'status', 'archived']),
  ZoneListData: object({ zones: array(ref('ZoneDto')) }, ['zones']),
  ZoneListResponse: object({
    data: ref('ZoneListData'),
    page: ref('PageInfo'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  CropSpeciesListData: object({ cropSpecies: array(ref('CropSpeciesDto')) }, ['cropSpecies']),
  CropSpeciesListResponse: object({
    data: ref('CropSpeciesListData'),
    page: ref('PageInfo'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  PlantingListData: object({ plantings: array(ref('PlantingDto')) }, ['plantings']),
  PlantingListResponse: object({
    data: ref('PlantingListData'),
    page: ref('PageInfo'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  HerdListData: object({ herds: array(ref('HerdDto')) }, ['herds']),
  HerdListResponse: object({
    data: ref('HerdListData'),
    page: ref('PageInfo'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  AnimalListData: object({ animals: array(ref('AnimalDto')) }, ['animals']),
  AnimalListResponse: object({
    data: ref('AnimalListData'),
    page: ref('PageInfo'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  WaterTankListData: object({ waterTanks: array(ref('WaterTankDto')) }, ['waterTanks']),
  WaterTankListResponse: object({
    data: ref('WaterTankListData'),
    page: ref('PageInfo'),
    meta: ref('ResponseMeta'),
  }, ['data', 'meta']),
  ScopedResponseMeta: object({
    schemaVersion: str(),
    asOf: ref('UtcInstant'),
    scopePolicyVersion: ref('PolicyVersion'),
  }, ['schemaVersion', 'asOf', 'scopePolicyVersion']),
  DomainMutationData: object({
    operationId: ref('Uuid'),
    outcome: str({ enum: ['applied', 'rejected', 'conflict', 'unknown'] }),
    revision: str({ pattern: '^(0|[1-9][0-9]*)$', description: 'Committed farm change revision as canonical decimal text.' }),
  }, ['operationId', 'outcome', 'revision'], {
    additionalProperties: true,
    description: 'Also carries the affected resource view under its resource key (for example farm or zone), including its resulting status and version.',
  }),
  DomainMutationResponse: object({
    data: ref('DomainMutationData'),
    meta: ref('ScopedResponseMeta'),
  }, ['data', 'meta']),
};

const operations = [];
function add(method, path, operationId, summary, options = {}) {
  operations.push({
    method: method.toLowerCase(), path, operationId, summary,
    tag: options.tag ?? 'Farmly',
    scope: options.scope ?? 'session',
    requestSchema: options.requestSchema,
    responseSchema: options.responseSchema,
    paginated: options.paginated ?? false,
    idempotentDomainWrite: options.idempotentDomainWrite ?? false,
    privateOwnerOnly: options.privateOwnerOnly ?? false,
    readOnlyAi: options.readOnlyAi ?? false,
    eventStream: options.eventStream ?? false,
    successStatus: options.successStatus ?? '200',
    notes: options.notes ?? summary,
  });
}
const O = '/v1/organizations/{orgId}';
const F = `${O}/farms/{farmId}`;
const body = (method, path, id, summary, schema = 'DomainCommandRequest', extra = {}) =>
  add(method, path, id, summary, { requestSchema: schema, ...extra });
const list = (path, id, summary, options = {}) =>
  add('GET', path, id, summary, { paginated: true, ...options });

add('GET', '/v1/me', 'getCurrentUser', 'Return the caller profile and safe session metadata.', { tag: 'Identity' });
list('/v1/organizations', 'listOrganizations', 'List organizations available to the caller.', { tag: 'Organizations' });
body('POST', '/v1/organizations', 'createOrganization', 'Create an organization and its initial owner atomically.', 'CreateOrganizationRequest', { tag: 'Organizations', scope: 'session', successStatus: '201', idempotentDomainWrite: true, notes: 'Requires Idempotency-Key to match body.operationId; a replay for the same actor returns OPERATION_ID_REUSED.' });
list(`${O}/farm-directory`, 'getFarmDirectory', 'Return one version-consistent page of the authorized farm directory.', { tag: 'Organizations', scope: 'organization', responseSchema: 'FarmDirectoryManifest', notes: 'Pages are UUID ordered and signed cursors bind organization, actor, policyVersion, continuityEpoch, last farm UUID, and page size. Each page uses one REPEATABLE READ snapshot. A changed version expires the cursor; the client must discard partial pages and restart. Never truncate or include unauthorized farm payloads.' });
body('POST', `${O}/sync/mutations`, 'submitOrganizationMutations', 'Admit only typed farm.create intents before a provisional farm exists.', 'FarmMutationBatch', { tag: 'Sync', scope: 'organization', notes: 'Recheck owner/admin authority; use the shared farm mutation kernel and initialize FarmClock atomically.' });
list('/v1/me/operation-status', 'getOwnOperationStatus', 'Return minimal statuses for this caller’s operation IDs.', { tag: 'Sync', paginated: false, notes: 'At most 50 operationIds; return only operationId and applied/rejected/unknown, with no resource or scope payload.' });
add('GET', O, 'getOrganization', 'Read organization summary and configuration.', { tag: 'Organizations', scope: 'organization' });
body('PATCH', O, 'patchOrganization', 'Update online organization configuration.', 'DomainCommandRequest', { tag: 'Organizations', scope: 'organization' });
list(`${O}/invitations`, 'listInvitations', 'List bounded organization invitations.', { tag: 'Organizations', scope: 'organization', responseSchema: 'OrganizationInvitationListResponse' });
body('POST', `${O}/invitations`, 'createInvitation', 'Create a verified-email invitation without sending through an unapproved adapter.', 'CreateOrganizationInvitationRequest', { tag: 'Organizations', scope: 'organization', successStatus: '201', responseSchema: 'CreatedOrganizationInvitationResponse', idempotentDomainWrite: true, notes: 'Token is returned once to the authorized creator and is never sent through an unapproved adapter; expiry is fixed at creation plus 72 hours.' });
body('POST', `${O}/invitations/{invitationId}/revoke`, 'revokeInvitation', 'Revoke an unaccepted invitation with fresh organization-manager authorization.', 'RevokeOrganizationInvitationRequest', { tag: 'Organizations', scope: 'organization', successStatus: '201', responseSchema: 'RevokedOrganizationInvitationResponse', idempotentDomainWrite: true, notes: 'Same actor/operation replay returns the existing revocation without another policyVersion increment; revoked invitations require a new token.' });
body('POST', `${O}/invitations/{invitationId}/accept`, 'acceptInvitation', 'Consume one matching verified-email invitation atomically.', 'AcceptOrganizationInvitationRequest', { tag: 'Organizations', scope: 'session', successStatus: '201', responseSchema: 'AcceptedOrganizationInvitationResponse', idempotentDomainWrite: true });
list(`${O}/memberships`, 'listOrganizationMemberships', 'List the bounded owner/admin membership roster and farm grants without profile PII.', { tag: 'Organizations', scope: 'organization', responseSchema: 'OrganizationMembershipListResponse', notes: 'Owner/admin only; stable UUID cursor; includes membership/user IDs, role/status/version and farm grants, never email or display-name data.' });
body('PATCH', `${O}/memberships/{membershipId}`, 'patchMembership', 'Replace a membership role and its complete farm-grant set under the organization lock.', 'PatchOrganizationMembershipRequest', { tag: 'Organizations', scope: 'organization', responseSchema: 'OrganizationMembershipMutationResponse', idempotentDomainWrite: true });
add('DELETE', `${O}/memberships/{membershipId}`, 'removeMembership', 'Soft-remove a membership and clear grants while preserving the last-owner invariant.', { tag: 'Organizations', scope: 'organization', responseSchema: 'OrganizationMembershipMutationResponse' });
body('POST', `${O}/ownership-transfers`, 'transferOrganizationOwnership', 'Transfer ownership atomically with a fresh uncached owner session.', 'TransferOrganizationOwnershipRequest', { tag: 'Organizations', scope: 'organization', responseSchema: 'OwnershipTransferResponse', idempotentDomainWrite: true });
list(`${O}/farms`, 'listFarms', 'List farms permitted to the caller.', { tag: 'Farms', scope: 'organization' });
body('POST', `${O}/farms`, 'createFarm', 'Create a farm through the typed farm.create mutation kernel.', 'FarmCreateMutation', { tag: 'Farms', scope: 'organization', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse', notes: 'Online resource ingress must use the same typed farm.create kernel, operation proof, and FarmClock initialization as offline admission.' });
add('GET', F, 'getFarm', 'Read one authorized farm profile.', { tag: 'Farms', scope: 'farm' });
body('PATCH', F, 'patchFarm', 'Update the farm profile through the mutation kernel.', 'FarmUpdateMutation', { tag: 'Farms', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
body('POST', `${F}/archive`, 'archiveFarm', 'Archive a farm without purging its records; intent resourceId must equal the farmId path parameter and payload is empty.', 'FarmArchiveMutation', { tag: 'Farms', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse', notes: 'The organization lock precedes the FarmClock lock; active status is rechecked after locking; meta.scopePolicyVersion increments atomically so farm-directory cursors expire.' });

for (const [slug, name] of [['zones', 'Zone'], ['crop-species', 'CropSpecies'], ['plantings', 'Planting']]) {
  const base = `${F}/${slug}`;
  const listOperationId = name === 'CropSpecies' ? 'listCropSpecies' : `list${name}s`;
  list(base, listOperationId, `List authorized ${slug} records.`, { tag: 'Farm data', scope: 'farm', responseSchema: `${name}ListResponse` });
  body('POST', base, `create${name}`, `Create a ${slug} record through the typed mutation kernel.`, `${name}CreateMutation`, { tag: 'Farm data', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
  body('PATCH', `${base}/{resourceId}`, `patch${name}`, `Compare-and-swap update one ${slug} record.`, `${name}UpdateMutation`, { tag: 'Farm data', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
  body('POST', `${base}/{resourceId}/archive`, `archive${name}`, `Archive one ${slug} record explicitly.`, `${name}ArchiveMutation`, { tag: 'Farm data', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
}
for (const [slug, name] of [['herds', 'Herd'], ['animals', 'Animal']]) {
  const base = `${F}/${slug}`;
  list(base, `list${name}s`, `List authorized ${slug}.`, { tag: 'Livestock', scope: 'farm', responseSchema: `${name}ListResponse` });
  body('POST', base, `create${name}`, `Create a ${slug} master record.`, `${name}CreateMutation`, { tag: 'Livestock', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
  body('PATCH', `${base}/{resourceId}`, `patch${name}`, `Compare-and-swap update a ${slug} master record.`, `${name}UpdateMutation`, { tag: 'Livestock', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
  body('POST', `${base}/{resourceId}/archive`, `archive${name}`, `Archive a ${slug} record explicitly; archive is distinct from animal status changes (sold, deceased).`, `${name}ArchiveMutation`, { tag: 'Livestock', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
}
for (const [slug, id, summary] of [
  ['livestock-movements', 'createLivestockMovement', 'Append a checked livestock movement.'],
  ['observations', 'createAnimalObservation', 'Append a manual animal observation.'],
  ['production-records', 'createProductionRecord', 'Append a unit-safe production fact.'],
]) body('POST', `${F}/${slug}`, id, summary, 'DomainCommandRequest', { tag: 'Livestock', scope: 'farm', idempotentDomainWrite: true });

list(`${F}/task-templates`, 'listTaskTemplates', 'List recurrence templates including watering tasks.', { tag: 'Tasks', scope: 'farm' });
body('POST', `${F}/task-templates`, 'createTaskTemplate', 'Create a recurrence template.', 'DomainCommandRequest', { tag: 'Tasks', scope: 'farm', idempotentDomainWrite: true });
body('PATCH', `${F}/task-templates/{templateId}`, 'patchTaskTemplate', 'Update a recurrence template.', 'DomainCommandRequest', { tag: 'Tasks', scope: 'farm', idempotentDomainWrite: true });
list(`${F}/task-occurrences`, 'listTaskOccurrences', 'List deterministic task occurrences.', { tag: 'Tasks', scope: 'farm' });
body('POST', `${F}/task-occurrences/{occurrenceId}/transitions`, 'transitionTaskOccurrence', 'Apply an assigned-worker or manager task transition using version CAS.', 'TaskTransitionRequest', { tag: 'Tasks', scope: 'farm', idempotentDomainWrite: true });
body('POST', `${F}/irrigation-tasks/{taskId}/transitions`, 'transitionIrrigationTask', 'Apply a watering task transition through the task kernel; no actuator or device API.', 'TaskTransitionRequest', { tag: 'Tasks', scope: 'farm', idempotentDomainWrite: true });

list(`${F}/harvests`, 'listHarvests', 'List immutable harvest facts and their effective heads.', { tag: 'Harvest', scope: 'farm' });
body('POST', `${F}/harvests`, 'createHarvest', 'Append an immutable harvest fact.', 'DomainCommandRequest', { tag: 'Harvest', scope: 'farm', idempotentDomainWrite: true });
body('POST', `${F}/harvests/{harvestId}/correction-proposals`, 'proposeHarvestCorrection', 'Propose a replacement quantity and reason.', 'DomainCommandRequest', { tag: 'Harvest', scope: 'farm', idempotentDomainWrite: true });
body('POST', `${F}/harvests/{harvestId}/corrections`, 'applyHarvestCorrection', 'Apply a manager-authorized correction using effective-head CAS.', 'DomainCommandRequest', { tag: 'Harvest', scope: 'farm', idempotentDomainWrite: true });
body('POST', `${F}/harvests/{harvestId}/void`, 'voidHarvest', 'Void an effective harvest with an authorized reason.', 'DomainCommandRequest', { tag: 'Harvest', scope: 'farm', idempotentDomainWrite: true });
list(`${F}/moisture-readings`, 'listMoistureReadings', 'List manual moisture readings by method and observation time.', { tag: 'Water', scope: 'farm' });
body('POST', `${F}/moisture-readings`, 'createMoistureReading', 'Append a validated manual moisture reading.', 'DomainCommandRequest', { tag: 'Water', scope: 'farm', idempotentDomainWrite: true });
list(`${F}/water-tanks`, 'listWaterTanks', 'List manual water tank records.', { tag: 'Water', scope: 'farm', responseSchema: 'WaterTankListResponse' });
body('POST', `${F}/water-tanks`, 'createWaterTank', 'Create a water tank master record.', 'WaterTankCreateMutation', { tag: 'Water', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
body('PATCH', `${F}/water-tanks/{tankId}`, 'patchWaterTank', 'Update a water tank using version CAS.', 'WaterTankUpdateMutation', { tag: 'Water', scope: 'farm', idempotentDomainWrite: true, responseSchema: 'DomainMutationResponse' });
body('POST', `${F}/water-readings`, 'createWaterReading', 'Append a manual tank-level observation.', 'DomainCommandRequest', { tag: 'Water', scope: 'farm', idempotentDomainWrite: true });
body('POST', `${F}/water-usage`, 'createWaterUsage', 'Append an immutable measured water-usage record.', 'DomainCommandRequest', { tag: 'Water', scope: 'farm', idempotentDomainWrite: true });
add('GET', `${F}/summary`, 'getFarmSummary', 'Return authorized farm totals and freshness metadata.', { tag: 'Analytics', scope: 'farm' });
add('GET', `${F}/analytics`, 'getFarmAnalytics', 'Return unit-safe, farm-local analytics.', { tag: 'Analytics', scope: 'farm' });
add('GET', `${F}/weather`, 'getFarmWeather', 'Return provider freshness and weather cache state.', { tag: 'Weather', scope: 'farm' });
body('POST', `${F}/sync/bootstrap`, 'createBootstrapSnapshot', 'Materialize a private Repeatable Read snapshot and immutable chunks.', 'DomainCommandRequest', { tag: 'Sync', scope: 'farm' });
add('GET', `${F}/sync/bootstrap/{snapshotId}`, 'getBootstrapChunk', 'Read one authorized immutable bootstrap page.', { tag: 'Sync', scope: 'farm' });
add('GET', `${F}/sync/changes`, 'getChangeSets', 'Read complete farm-scoped committed change sets in revision order.', { tag: 'Sync', scope: 'farm' });
body('POST', `${F}/sync/mutations`, 'submitFarmMutations', 'Apply up to 50 typed, immutable farm-scoped operations.', 'FarmMutationBatch', { tag: 'Sync', scope: 'farm', notes: 'Recheck current session and grants; preserve one atomic ChangeSet per committed farm revision.' });

body('POST', `${F}/ai/requests`, 'createAiRequest', 'Reserve budget and create one private read-only AI request.', 'AiCreateRequest', { tag: 'Private AI', scope: 'farm-private', privateOwnerOnly: true, readOnlyAi: true, successStatus: '202', notes: 'Requires explicit current consent and server-owned provider configuration. Never performs a farm mutation.' });
add('GET', `${F}/ai/requests/{requestId}/events`, 'streamAiRequestEvents', 'Replay and stream persisted events for the exact private request.', { tag: 'Private AI', scope: 'farm-private', privateOwnerOnly: true, readOnlyAi: true, eventStream: true, notes: 'Persist before emission; Last-Event-ID is bound to this request. Disconnect/replay never causes a new provider call.' });
body('POST', `${F}/ai/requests/{requestId}/cancel`, 'cancelAiRequest', 'Request best-effort cancellation for the caller’s private request.', 'AiCancelRequest', { tag: 'Private AI', scope: 'farm-private', privateOwnerOnly: true, readOnlyAi: true, successStatus: '202' });
add('GET', `${F}/ai/requests/{requestId}`, 'getAiRequestStatus', 'Return the caller-owned private request status or final response.', { tag: 'Private AI', scope: 'farm-private', privateOwnerOnly: true, readOnlyAi: true });
list(`${F}/ai/conversations`, 'listAiConversations', 'List only the current caller’s private conversations.', { tag: 'Private AI', scope: 'farm-private', privateOwnerOnly: true, readOnlyAi: true });
list(`${F}/ai/conversations/{conversationId}/messages`, 'listAiConversationMessages', 'List messages only for the private conversation owner.', { tag: 'Private AI', scope: 'farm-private', privateOwnerOnly: true, readOnlyAi: true });
body('PUT', `${O}/ai/consent`, 'setAiConsent', 'Grant or update the caller’s private AI context consent for this organization.', 'AiConsentDecision', { tag: 'Private AI', scope: 'organization', privateOwnerOnly: true, readOnlyAi: true, notes: 'Consent state is a per-(user, organization) singleton. An unchanged decision returns the current revision without invalidating in-flight requests; any change bumps the consent revision and withdraws queued-not-dispatched requests server-side.' });
list('/v1/me/notifications', 'listOwnNotifications', 'List notifications addressed to the current recipient.', { tag: 'Notifications', scope: 'session' });
body('POST', '/v1/me/notifications/{notificationId}/read', 'markOwnNotificationRead', 'Mark one recipient-owned notification as read.', 'DomainCommandRequest', { tag: 'Notifications', scope: 'session' });
body('POST', '/v1/me/device-registrations', 'mutateOwnDeviceRegistration', 'Register or revoke the caller’s push token without logging it.', 'DeviceRegistrationRequest', { tag: 'Notifications', scope: 'session' });
body('POST', '/v1/me/privacy-requests', 'createPrivacyRequest', 'Start an authorized export, deletion, or consent-withdrawal request.', 'PrivacyRequest', { tag: 'Privacy', scope: 'session', successStatus: '202' });

function operationParameters(item) {
  const pathParameters = [...item.path.matchAll(/\{([^}]+)\}/g)].map((match) => ({
    name: match[1],
    in: 'path',
    required: true,
    schema: ref('Uuid'),
  }));
  const parameters = [...pathParameters];
  if (item.idempotentDomainWrite) {
    parameters.push({ name: 'Idempotency-Key', in: 'header', required: true, schema: ref('Uuid'), description: 'Must equal body.operationId.' });
  }
  if (item.paginated) {
    parameters.push(
      { name: 'limit', in: 'query', required: false, schema: int({ minimum: 1, maximum: 100, default: 25 }) },
      { name: 'cursor', in: 'query', required: false, schema: item.operationId === 'listOrganizationMemberships' ? ref('Uuid') : item.operationId === 'getFarmDirectory' ? str({ minLength: 1, maxLength: 2048 }) : str() },
    );
  }
  if (item.operationId === 'getOwnOperationStatus') {
    parameters.push({ name: 'operationIds', in: 'query', required: true, style: 'form', explode: false, schema: array(ref('Uuid'), { minItems: 1, maxItems: 50 }) });
  }
  if (item.operationId === 'getChangeSets') {
    parameters.push({ name: 'cursor', in: 'query', required: true, schema: str() });
  }
  if (item.operationId === 'getBootstrapChunk') {
    parameters.push({ name: 'pageCursor', in: 'query', required: false, schema: str() });
  }
  if (item.operationId === 'streamAiRequestEvents') {
    parameters.push({ name: 'Last-Event-ID', in: 'header', required: false, schema: str() });
  }
  return parameters;
}

function buildResponses(item) {
  const successContent = item.eventStream
    ? { 'text/event-stream': { schema: str(), description: 'Persisted farmly-ai-events.v1 JSON data frames; heartbeat comments are not semantic events.' } }
    : { 'application/json': { schema: ref(item.responseSchema ?? 'SuccessEnvelope') } };
  const responses = {
    [item.successStatus]: { description: 'Successful response.', content: successContent },
  };
  for (const [status, description] of [
    ['400', 'Malformed or out-of-range request.'],
    ['401', 'Missing or invalid Better Auth session.'],
    ['403', 'Known scope revoked or action forbidden.'],
    ['404', 'Unknown or unauthorized object; no cross-scope enumeration.'],
    ['409', 'Version, idempotency, reconciliation, or bootstrap-size conflict.'],
    ['410', 'Authorized cursor or snapshot expired.'],
    ['422', 'Field validation failed.'],
    ['429', 'Rate or AI quota limit reached before dispatch.'],
    ['502', 'Sanitized upstream failure.'],
    ['503', 'Service temporarily unavailable.'],
  ]) responses[status] = { description, content: { 'application/json': { schema: ref('ErrorEnvelope') } } };
  return responses;
}

export function buildOpenApi() {
  const paths = {};
  for (const item of operations) {
    const pathItem = paths[item.path] ??= {};
    if (pathItem[item.method]) throw new Error(`Duplicate OpenAPI operation: ${item.method} ${item.path}`);
    const operation = {
      operationId: item.operationId,
      tags: [item.tag],
      summary: item.summary,
      description: item.notes,
      security: [{ betterAuthSession: [] }],
      parameters: operationParameters(item),
      responses: buildResponses(item),
      'x-farmly-scope': item.scope,
      'x-farmly-private-owner-only': item.privateOwnerOnly,
      'x-farmly-ai-no-farm-mutation': item.readOnlyAi,
    };
    if (item.requestSchema) {
      operation.requestBody = {
        required: true,
        content: { 'application/json': { schema: ref(item.requestSchema) } },
      };
    }
    if (item.paginated) operation['x-farmly-page-default'] = 25;
    if (item.idempotentDomainWrite) operation['x-farmly-idempotency'] = 'Idempotency-Key equals body.operationId';
    pathItem[item.method] = operation;
  }
  return {
    openapi: '3.1.1',
    info: {
      title: 'Farmly API v1',
      version: '1.0.0',
      description: 'Contract derived from specs/04-data-api-sync-contract.md and specs/05-chatbot-provider-evaluation.md. This file is JSON syntax, which is a valid YAML 1.2 subset; it is generated deterministically without a YAML parser dependency.',
    },
    servers: [{ url: 'http://localhost:3000', description: 'Local Farmly API scaffold only.' }],
    tags: ['Identity', 'Organizations', 'Farms', 'Farm data', 'Livestock', 'Tasks', 'Harvest', 'Water', 'Analytics', 'Weather', 'Sync', 'Private AI', 'Notifications', 'Privacy'].map((name) => ({ name })),
    security: [{ betterAuthSession: [] }],
    paths,
    components: {
      securitySchemes: {
        betterAuthSession: {
          type: 'apiKey',
          in: 'cookie',
          name: 'better-auth.session_token',
          description: 'Opaque session cookie produced and validated by the pinned Better Auth adapter. Mobile clients use the auth adapter; no JWT/refresh-token family is implied. Secure-cookie prefixes may be applied by deployment configuration.',
        },
      },
      schemas,
    },
    'x-farmly-required-endpoints': operations.map(({ method, path, operationId }) => ({ method: method.toUpperCase(), path, operationId })),
    'x-farmly-ai-event-types': aiEventTypes,
    'x-farmly-bootstrap-entities': bootstrapEntities,
    'x-farmly-bootstrap-exclusions': [
      'weather snapshots are freshness-bounded read caches outside the committed change feed',
      'private AI, auth/session, directory control-plane, operation proof, and notification records are not farm bootstrap rows',
    ],
  };
}

function sha256(content) {
  return createHash('sha256').update(content).digest('hex');
}

function schemaType(schema, schemaName) {
  if (schema.$ref) {
    const target = schema.$ref.split('/').at(-1);
    if (target === 'DecimalString' || target === 'AreaM2String' || target === 'UnitInterval') return 'FarmlyDecimal';
    if (schemas[target]?.type === 'object') return `Farmly${target}`;
    return 'String';
  }
  if (Array.isArray(schema.type)) {
    const type = schema.type.find((value) => value !== 'null');
    return schemaType({ ...schema, type }, schemaName);
  }
  if (schema.type === 'array') return `List<${schemaType(schema.items ?? {}, schemaName)}>`;
  if (schema.type === 'integer' || schema.type === 'number') return 'int';
  if (schema.type === 'boolean') return 'bool';
  if (schema.type === 'object') return 'Map<String, dynamic>';
  return 'String';
}

function nullable(schema) {
  return Array.isArray(schema.type) && schema.type.includes('null');
}

function fromJsonExpression(schema, key) {
  if (schema.$ref) {
    const target = schema.$ref.split('/').at(-1);
    if (target === 'DecimalString' || target === 'AreaM2String' || target === 'UnitInterval') return `FarmlyDecimal.parse(json['${key}'] as String)`;
    if (schemas[target]?.type === 'object') return `Farmly${target}.fromJson(Map<String, dynamic>.from(json['${key}'] as Map))`;
    return `json['${key}'] as String`;
  }
  if (Array.isArray(schema.type)) return fromJsonExpression({ ...schema, type: schema.type.find((type) => type !== 'null') }, key);
  if (schema.type === 'array') {
    const item = schema.items ?? {};
    if (item.$ref && schemas[item.$ref.split('/').at(-1)]?.type === 'object') {
      const name = item.$ref.split('/').at(-1);
      return `(json['${key}'] as List<dynamic>).map((item) => Farmly${name}.fromJson(Map<String, dynamic>.from(item as Map))).toList(growable: false)`;
    }
    if (item.type === 'object') return `(json['${key}'] as List<dynamic>).map((item) => Map<String, dynamic>.from(item as Map)).toList(growable: false)`;
    return `(json['${key}'] as List<dynamic>).cast<${schemaType(item)}>()`;
  }
  if (schema.type === 'object') return `Map<String, dynamic>.from(json['${key}'] as Map)`;
  if (schema.type === 'integer' || schema.type === 'number') return `json['${key}'] as int`;
  if (schema.type === 'boolean') return `json['${key}'] as bool`;
  return `json['${key}'] as String`;
}

function toJsonExpression(schema, name, optional = false) {
  if (schema.$ref) {
    const target = schema.$ref.split('/').at(-1);
    if (target === 'DecimalString' || target === 'AreaM2String' || target === 'UnitInterval') return `${name}${optional ? '?' : ''}.value`;
    if (schemas[target]?.type === 'object') return `${name}${optional ? '?' : ''}.toJson()`;
    return name;
  }
  if (Array.isArray(schema.type)) return toJsonExpression({ ...schema, type: schema.type.find((type) => type !== 'null') }, name, optional);
  if (schema.type === 'array') {
    const item = schema.items ?? {};
    if (item.$ref && schemas[item.$ref.split('/').at(-1)]?.type === 'object') return `${name}${optional ? '?' : ''}.map((item) => item.toJson()).toList(growable: false)`;
    if (item.type === 'object') return `${name}${optional ? '?' : ''}.map((item) => item).toList(growable: false)`;
  }
  return name;
}

export function renderDartTypes(openapiText) {
  const document = JSON.parse(openapiText);
  const mutationTypeValues = document.components.schemas.FarmMutation?.properties?.type?.enum;
  if (!Array.isArray(mutationTypeValues) || mutationTypeValues.length === 0) {
    throw new Error('FarmMutation.type must define a non-empty canonical enum');
  }
  const hash = sha256(openapiText);
  const lines = [
    '// GENERATED FILE. Run node contracts/scripts/build-contracts.mjs to refresh.',
    `// OpenAPI SHA-256: ${hash}`,
    '',
    'typedef FarmlyJsonMap = Map<String, dynamic>;',
    '',
    '/// Canonical operation types accepted by the Farmly mutation protocol.',
    'const Set<String> farmlyMutationTypes = <String>{',
    ...mutationTypeValues.map((type) => `  ${JSON.stringify(type)},`),
    '};',
    '',
    '/// Exact base-10 wire value. It intentionally avoids floating-point conversion.',
    'final class FarmlyDecimal {',
    '  static final RegExp _canonical = RegExp(r\'^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?$\');',
    '  final String value;',
    '  const FarmlyDecimal._(this.value);',
    '  factory FarmlyDecimal.parse(String value) {',
    '    if (!_canonical.hasMatch(value)) {',
    '      throw const FormatException(\'Invalid canonical decimal string\');',
    '    }',
    '    return FarmlyDecimal._(value);',
    '  }',
    '  @override String toString() => value;',
    '  @override bool operator ==(Object other) => other is FarmlyDecimal && other.value == value;',
    '  @override int get hashCode => value.hashCode;',
    '}',
    '',
  ];
  for (const [name, schema] of Object.entries(document.components.schemas)) {
    if (schema.type !== 'object') continue;
    const className = `Farmly${name}`;
    const required = new Set(schema.required ?? []);
    const fields = Object.entries(schema.properties ?? {});
    lines.push(`final class ${className} {`);
    if (fields.length === 0) {
      lines.push(`  const ${className}();`, '  factory ' + className + '.fromJson(FarmlyJsonMap json) => const ' + className + '();', '  FarmlyJsonMap toJson() => <String, dynamic>{};', '}\n');
      continue;
    }
    lines.push(`  const ${className}({`);
    for (const [key, schemaProperty] of fields) {
      const modifier = required.has(key) ? 'required ' : '';
      lines.push(`    ${modifier}this.${key},`);
    }
    lines.push('  });');
    for (const [key, schemaProperty] of fields) {
      const type = schemaType(schemaProperty, name);
      lines.push(`  final ${type}${required.has(key) && !nullable(schemaProperty) ? '' : '?'} ${key};`);
    }
    lines.push(`  factory ${className}.fromJson(FarmlyJsonMap json) => ${className}(`);
    for (const [key, schemaProperty] of fields) {
      const expression = fromJsonExpression(schemaProperty, key);
      const nullableExpr = !required.has(key) || nullable(schemaProperty) ? `(json['${key}'] == null ? null : ${expression})` : expression;
      lines.push(`    ${key}: ${nullableExpr},`);
    }
    lines.push('  );', '  FarmlyJsonMap toJson() {', '    final json = <String, dynamic>{');
    for (const [key, schemaProperty] of fields) {
      const optional = !required.has(key) || nullable(schemaProperty);
      const value = toJsonExpression(schemaProperty, key, optional);
      lines.push(`      '${key}': ${value},`);
    }
    lines.push("    }..removeWhere((key, value) => value == null);", '    return json;', '  }', '}\n');
  }
  return formatDart(lines.join('\n'));
}

function dartExecutable() {
  if (process.platform !== 'win32') return 'dart';
  const matches = execFileSync('where.exe', ['dart'], { encoding: 'utf8' }).split(/\r?\n/).filter(Boolean);
  for (const candidate of matches) {
    if (/\\dart\.exe$/i.test(candidate) && existsSync(candidate)) return candidate;
    const bundled = resolve(dirname(candidate), 'cache', 'dart-sdk', 'bin', 'dart.exe');
    if (existsSync(bundled)) return bundled;
  }
  throw new Error('DART_FORMAT_UNAVAILABLE');
}

function formatDart(source) {
  const tempRoot = realpathSync(tmpdir());
  const tempDirectory = resolve(mkdtempSync(join(tempRoot, 'farmly-contract-')));
  const relativeTemp = relative(tempRoot, tempDirectory);
  if (relativeTemp === '..' || relativeTemp.startsWith(`..${sep}`)) throw new Error('TEMP_PATH_BOUNDARY');
  const tempFile = join(tempDirectory, 'farmly_api_types.dart');
  try {
    writeFileSync(tempFile, source, 'utf8');
    execFileSync(dartExecutable(), ['format', '--output=write', tempFile], { stdio: 'ignore' });
    return readFileSync(tempFile, 'utf8');
  } finally {
    const realTemp = realpathSync(tempDirectory);
    const rel = relative(tempRoot, realTemp);
    if (rel !== '..' && !rel.startsWith(`..${sep}`) && rel !== '') rmSync(realTemp, { recursive: true, force: true });
  }
}

function outputs() {
  const document = buildOpenApi();
  const openapiText = `${JSON.stringify(document, null, 2)}\n`;
  const dartText = renderDartTypes(openapiText);
  return new Map([[OPENAPI_PATH, openapiText], [DART_PATH, dartText]]);
}

function writeOrCheck(checkOnly) {
  let failed = false;
  for (const [repoPath, content] of outputs()) {
    const absolute = resolve(ROOT, repoPath);
    if (checkOnly) {
      let current;
      try { current = readFileSync(absolute, 'utf8'); } catch { current = null; }
      if (current !== content) {
        console.error(`DRIFT ${repoPath}`);
        failed = true;
      } else {
        console.log(`PASS ${repoPath}`);
      }
      continue;
    }
    mkdirSync(dirname(absolute), { recursive: true });
    writeFileSync(absolute, content, 'utf8');
    console.log(`WROTE ${repoPath}`);
  }
  if (failed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const args = new Set(process.argv.slice(2));
  if (args.has('--help')) {
    console.log('Usage: node contracts/scripts/build-contracts.mjs [--check]');
  } else if ([...args].some((arg) => !['--check'].includes(arg))) {
    console.error('ERROR CONTRACT_ARGS');
    process.exitCode = 2;
  } else {
    writeOrCheck(args.has('--check'));
  }
}
