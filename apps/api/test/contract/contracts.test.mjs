import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { bootstrapEntities, buildOpenApi } from '../../../../contracts/scripts/build-contracts.mjs';
import { measureFixture } from '../../../../tools/qa/measure-bootstrap-fixture.mjs';

const ROOT = fileURLToPath(new URL('../../../../', import.meta.url));
const PLAN_REPORTS = 'plans/261005-1435-farmly-mobile-app/reports/';
const openapiPath = resolve(ROOT, 'contracts/openapi/farmly-v1.yaml');
const dartPath = resolve(ROOT, 'apps/mobile/lib/generated/farmly_api_types.dart');
const fixturePath = resolve(ROOT, 'tools/qa/fixtures/bootstrap-supported-v1.json');
const generatorPath = resolve(ROOT, 'contracts/scripts/build-contracts.mjs');
const sizingToolPath = resolve(ROOT, 'tools/qa/measure-bootstrap-fixture.mjs');
const openapiText = readFileSync(openapiPath, 'utf8');
const openapi = JSON.parse(openapiText);

const requiredRoutes = [
  'GET /v1/me',
  'GET /v1/organizations',
  'POST /v1/organizations',
  'GET /v1/organizations/{orgId}/farm-directory',
  'POST /v1/organizations/{orgId}/sync/mutations',
  'GET /v1/me/operation-status',
  'GET /v1/organizations/{orgId}',
  'PATCH /v1/organizations/{orgId}',
  'GET /v1/organizations/{orgId}/invitations',
  'POST /v1/organizations/{orgId}/invitations',
  'POST /v1/organizations/{orgId}/invitations/{invitationId}/revoke',
  'POST /v1/organizations/{orgId}/invitations/{invitationId}/accept',
  'GET /v1/organizations/{orgId}/memberships',
  'PATCH /v1/organizations/{orgId}/memberships/{membershipId}',
  'DELETE /v1/organizations/{orgId}/memberships/{membershipId}',
  'POST /v1/organizations/{orgId}/ownership-transfers',
  'GET /v1/organizations/{orgId}/farms',
  'POST /v1/organizations/{orgId}/farms',
  'GET /v1/organizations/{orgId}/farms/{farmId}',
  'PATCH /v1/organizations/{orgId}/farms/{farmId}',
  'POST /v1/organizations/{orgId}/farms/{farmId}/archive',
  ...['zones', 'crop-species', 'plantings'].flatMap((resource) => [
    `GET /v1/organizations/{orgId}/farms/{farmId}/${resource}`,
    `POST /v1/organizations/{orgId}/farms/{farmId}/${resource}`,
    `PATCH /v1/organizations/{orgId}/farms/{farmId}/${resource}/{resourceId}`,
    `POST /v1/organizations/{orgId}/farms/{farmId}/${resource}/{resourceId}/archive`,
  ]),
  ...['herds', 'animals'].flatMap((resource) => [
    `GET /v1/organizations/{orgId}/farms/{farmId}/${resource}`,
    `POST /v1/organizations/{orgId}/farms/{farmId}/${resource}`,
    `PATCH /v1/organizations/{orgId}/farms/{farmId}/${resource}/{resourceId}`,
    `POST /v1/organizations/{orgId}/farms/{farmId}/${resource}/{resourceId}/archive`,
  ]),
  'POST /v1/organizations/{orgId}/farms/{farmId}/livestock-movements',
  'POST /v1/organizations/{orgId}/farms/{farmId}/observations',
  'POST /v1/organizations/{orgId}/farms/{farmId}/production-records',
  'GET /v1/organizations/{orgId}/farms/{farmId}/task-templates',
  'POST /v1/organizations/{orgId}/farms/{farmId}/task-templates',
  'PATCH /v1/organizations/{orgId}/farms/{farmId}/task-templates/{templateId}',
  'GET /v1/organizations/{orgId}/farms/{farmId}/task-occurrences',
  'POST /v1/organizations/{orgId}/farms/{farmId}/task-occurrences/{occurrenceId}/transitions',
  'POST /v1/organizations/{orgId}/farms/{farmId}/irrigation-tasks/{taskId}/transitions',
  'GET /v1/organizations/{orgId}/farms/{farmId}/harvests',
  'POST /v1/organizations/{orgId}/farms/{farmId}/harvests',
  'POST /v1/organizations/{orgId}/farms/{farmId}/harvests/{harvestId}/correction-proposals',
  'POST /v1/organizations/{orgId}/farms/{farmId}/harvests/{harvestId}/corrections',
  'POST /v1/organizations/{orgId}/farms/{farmId}/harvests/{harvestId}/void',
  'GET /v1/organizations/{orgId}/farms/{farmId}/moisture-readings',
  'POST /v1/organizations/{orgId}/farms/{farmId}/moisture-readings',
  'GET /v1/organizations/{orgId}/farms/{farmId}/water-tanks',
  'POST /v1/organizations/{orgId}/farms/{farmId}/water-tanks',
  'PATCH /v1/organizations/{orgId}/farms/{farmId}/water-tanks/{tankId}',
  'POST /v1/organizations/{orgId}/farms/{farmId}/water-readings',
  'POST /v1/organizations/{orgId}/farms/{farmId}/water-usage',
  'GET /v1/organizations/{orgId}/farms/{farmId}/summary',
  'GET /v1/organizations/{orgId}/farms/{farmId}/analytics',
  'GET /v1/organizations/{orgId}/farms/{farmId}/weather',
  'POST /v1/organizations/{orgId}/farms/{farmId}/sync/bootstrap',
  'GET /v1/organizations/{orgId}/farms/{farmId}/sync/bootstrap/{snapshotId}',
  'GET /v1/organizations/{orgId}/farms/{farmId}/sync/changes',
  'POST /v1/organizations/{orgId}/farms/{farmId}/sync/mutations',
  'POST /v1/organizations/{orgId}/farms/{farmId}/ai/requests',
  'GET /v1/organizations/{orgId}/farms/{farmId}/ai/requests/{requestId}/events',
  'POST /v1/organizations/{orgId}/farms/{farmId}/ai/requests/{requestId}/cancel',
  'GET /v1/organizations/{orgId}/farms/{farmId}/ai/requests/{requestId}',
  'GET /v1/organizations/{orgId}/farms/{farmId}/ai/conversations',
  'GET /v1/organizations/{orgId}/farms/{farmId}/ai/conversations/{conversationId}/messages',
  'PUT /v1/organizations/{orgId}/ai/consent',
  'GET /v1/me/notifications',
  'POST /v1/me/notifications/{notificationId}/read',
  'POST /v1/me/device-registrations',
  'POST /v1/me/privacy-requests',
];

function actualRoutes(document) {
  return Object.entries(document.paths).flatMap(([path, pathItem]) =>
    Object.keys(pathItem).filter((method) => ['get', 'post', 'patch', 'put', 'delete'].includes(method))
      .map((method) => `${method.toUpperCase()} ${path}`));
}

function collectRefs(value, result = []) {
  if (Array.isArray(value)) {
    for (const item of value) collectRefs(item, result);
  } else if (value && typeof value === 'object') {
    if (typeof value.$ref === 'string') result.push(value.$ref);
    for (const nested of Object.values(value)) collectRefs(nested, result);
  }
  return result;
}

describe('Farmly v1 contract', () => {
  it('contains every planned endpoint and action exactly once', () => {
    const actual = actualRoutes(openapi).sort();
    expect(actual).toEqual([...requiredRoutes].sort());
    expect(new Set(actual).size).toBe(actual.length);
    expect(openapi['x-farmly-required-endpoints']).toHaveLength(requiredRoutes.length);
    expect(buildOpenApi()).toEqual(openapi);
    const operationIds = openapi['x-farmly-required-endpoints'].map((route) => route.operationId);
    expect(new Set(operationIds).size).toBe(operationIds.length);
    for (const reference of collectRefs(openapi)) {
      expect(reference.startsWith('#/components/schemas/')).toBe(true);
      expect(openapi.components.schemas).toHaveProperty(reference.split('/').at(-1));
    }
    for (const [path, pathItem] of Object.entries(openapi.paths)) {
      for (const [method, operation] of Object.entries(pathItem)) {
        if (!['get', 'post', 'patch', 'put', 'delete'].includes(method)) continue;
        const placeholders = [...path.matchAll(/\{([^}]+)\}/g)].map((match) => match[1]).sort();
        const declared = operation.parameters.filter((parameter) => parameter.in === 'path').map((parameter) => parameter.name).sort();
        expect(declared).toEqual(placeholders);
        expect(operation.parameters.filter((parameter) => parameter.in === 'path').every((parameter) => parameter.required)).toBe(true);
      }
    }
  });

  it('keeps Decimal, scope, errors, and typed mutations safe on the wire', () => {
    const schemas = openapi.components.schemas;
    expect(schemas.DecimalString).toMatchObject({ type: 'string', format: 'decimal-string' });
    expect(schemas.DecimalString.pattern).toBeDefined();
    expect(schemas.PolicyVersion).toMatchObject({
      type: 'string',
      format: 'positive-decimal-string',
      pattern: '^[1-9][0-9]*$',
    });
    expect(schemas.FarmMutation.properties.type.enum).toContain('irrigationTask.transition');
    expect(schemas.FarmMutation.properties.payload.additionalProperties).toBe(true);
    expect(Object.keys(schemas.FarmMutation.properties)).not.toEqual(expect.arrayContaining(['actorId', 'organizationId', 'farmId']));
    expect(schemas.FarmDirectoryManifest.required).toContain('continuityEpoch');
    expect(schemas.FarmDirectoryManifest.properties.scopePolicyVersion)
      .toEqual({ $ref: '#/components/schemas/PolicyVersion' });
    expect(schemas.FarmScope.properties.scopePolicyVersion)
      .toEqual({ $ref: '#/components/schemas/PolicyVersion' });
    expect(schemas.ResponseMeta.properties.scopePolicyVersion)
      .toEqual({ $ref: '#/components/schemas/PolicyVersion' });
    const farmDirectory = openapi.paths['/v1/organizations/{orgId}/farm-directory'].get;
    expect(farmDirectory.responses['200'].content['application/json'].schema)
      .toEqual({ $ref: '#/components/schemas/FarmDirectoryManifest' });
    expect(farmDirectory.parameters.map((parameter) => parameter.in)).toEqual(['path', 'query', 'query']);
    expect(farmDirectory.parameters.find((parameter) => parameter.name === 'limit').schema)
      .toMatchObject({ minimum: 1, maximum: 100, default: 25 });
    expect(farmDirectory.parameters.find((parameter) => parameter.name === 'cursor').schema)
      .toMatchObject({ type: 'string', minLength: 1, maxLength: 2048 });
    expect(farmDirectory['x-farmly-page-default']).toBe(25);
    expect(farmDirectory.description).toContain('REPEATABLE READ');
    expect(schemas.FarmDirectoryManifest.required).not.toContain('nextCursor');
    expect(schemas.FarmDirectoryManifest.properties.nextCursor.maxLength).toBe(2048);
    expect(schemas.OperationStatus.properties).toEqual({
      operationId: { $ref: '#/components/schemas/Uuid' },
      outcome: { type: 'string', enum: ['applied', 'rejected', 'unknown'] },
    });
    expect(schemas.ErrorEnvelope.properties.error.$ref).toBe('#/components/schemas/ApiError');
    expect(schemas.FarmlyErrorCode.enum).toEqual(expect.arrayContaining([
      'INVITATION_NOT_AVAILABLE',
      'INVITATION_EMAIL_MISMATCH',
      'INVITATION_EXPIRED',
      'INVITATION_REVOKED',
      'INVITATION_ALREADY_ACCEPTED',
      'MEMBERSHIP_ALREADY_EXISTS',
    ]));
    expect(openapi.components.securitySchemes.betterAuthSession.type).toBe('apiKey');
    expect(openapi.components.securitySchemes.betterAuthSession.in).toBe('cookie');
    expect(openapi.components.securitySchemes.betterAuthSession).not.toHaveProperty('scheme', 'bearer');
  });

  it('keeps organization farm creation on the shared typed mutation contract', () => {
    const schemas = openapi.components.schemas;
    const createFarm = openapi.paths['/v1/organizations/{orgId}/farms'].post;
    const submitOrganizationMutations = openapi.paths['/v1/organizations/{orgId}/sync/mutations'].post;
    const ownOperationStatus = openapi.paths['/v1/me/operation-status'].get;

    expect(createFarm.parameters).toContainEqual(expect.objectContaining({
      name: 'Idempotency-Key',
      in: 'header',
      required: true,
      description: 'Must equal body.operationId.',
    }));
    expect(createFarm.requestBody.content['application/json'].schema)
      .toEqual({ $ref: '#/components/schemas/FarmCreateMutation' });
    expect(createFarm.responses).toHaveProperty('200');
    expect(createFarm.responses).not.toHaveProperty('201');
    expect(createFarm.description).toContain('same typed farm.create kernel');
    expect(submitOrganizationMutations.requestBody.content['application/json'].schema)
      .toEqual({ $ref: '#/components/schemas/FarmMutationBatch' });
    expect(submitOrganizationMutations.summary).toContain('only typed farm.create intents');
    expect(schemas.FarmMutationBatch.properties.operations.items)
      .toEqual({ $ref: '#/components/schemas/FarmMutation' });
    expect(schemas.FarmMutationBatch.properties.operations).toMatchObject({ minItems: 1, maxItems: 50 });
    expect(schemas.FarmMutation.additionalProperties).toBe(false);
    expect(schemas.FarmMutation.properties.payload.additionalProperties).toBe(true);
    expect(schemas.MutationBatchResult.properties.outcomes.items)
      .toEqual({ $ref: '#/components/schemas/FarmMutationOutcome' });
    expect(schemas.FarmMutationOutcome.properties.outcome.enum)
      .toEqual(['applied', 'rejected', 'conflict', 'unknown']);
    expect(ownOperationStatus.parameters[0]).toMatchObject({
      name: 'operationIds',
      in: 'query',
      required: true,
      explode: false,
    });
    expect(ownOperationStatus.parameters[0].schema).toMatchObject({ minItems: 1, maxItems: 50 });
    expect(schemas.OperationStatus.properties).toEqual({
      operationId: { $ref: '#/components/schemas/Uuid' },
      outcome: { type: 'string', enum: ['applied', 'rejected', 'unknown'] },
    });
  });

  it('pins the P05 domain wire contract: strict mutation envelopes, DTOs, and archive routes', () => {
    const schemas = openapi.components.schemas;
    const O = '/v1/organizations/{orgId}';
    const F = `${O}/farms/{farmId}`;
    const bodyRef = (path, method) =>
      openapi.paths[path][method].requestBody.content['application/json'].schema.$ref.split('/').at(-1);
    const successRef = (path, method) =>
      openapi.paths[path][method].responses['200'].content['application/json'].schema.$ref.split('/').at(-1);

    const writes = [
      ['post', `${O}/farms`, 'FarmCreateMutation'],
      ['patch', F, 'FarmUpdateMutation'],
      ['post', `${F}/archive`, 'FarmArchiveMutation'],
    ];
    for (const [slug, pascal] of [['zones', 'Zone'], ['crop-species', 'CropSpecies'], ['plantings', 'Planting'], ['herds', 'Herd'], ['animals', 'Animal']]) {
      writes.push(
        ['post', `${F}/${slug}`, `${pascal}CreateMutation`],
        ['patch', `${F}/${slug}/{resourceId}`, `${pascal}UpdateMutation`],
        ['post', `${F}/${slug}/{resourceId}/archive`, `${pascal}ArchiveMutation`],
      );
    }
    writes.push(
      ['post', `${F}/water-tanks`, 'WaterTankCreateMutation'],
      ['patch', `${F}/water-tanks/{tankId}`, 'WaterTankUpdateMutation'],
    );

    for (const [method, path, schemaName] of writes) {
      expect(bodyRef(path, method)).toBe(schemaName);
      expect(successRef(path, method)).toBe('DomainMutationResponse');
      expect(openapi.paths[path][method].parameters).toContainEqual(expect.objectContaining({
        name: 'Idempotency-Key', in: 'header', required: true,
      }));
      const schema = schemas[schemaName];
      expect(schema.additionalProperties).toBe(false);
      expect(schema.properties.schemaVersion.const).toBe('farm-mutation.v1');
      const mutationType = schema.properties.type.const;
      expect(mutationType).toMatch(/^[a-zA-Z]+\.(create|update|archive)$/);
      expect(schemas.FarmMutation.properties.type.enum).toContain(mutationType);
      for (const field of ['schemaVersion', 'continuityEpoch', 'operationId', 'type', 'resourceId', 'dependsOn', 'payload']) {
        expect(schema.required).toContain(field);
      }
      expect(schema.properties.operationId.$ref).toBe('#/components/schemas/Uuid');
      expect(schema.properties.resourceId.$ref).toBe('#/components/schemas/Uuid');
      if (mutationType.endsWith('.create')) {
        expect(schema.required).not.toContain('baseVersion');
        expect(schema.properties.baseVersion.type).toBe('null');
      } else {
        expect(schema.required).toContain('baseVersion');
        expect(schema.properties.baseVersion).toMatchObject({ type: 'integer', minimum: 1 });
      }
      const payloadName = schema.properties.payload.$ref.split('/').at(-1);
      expect(schemas[payloadName]).toMatchObject({ type: 'object', additionalProperties: false });
    }

    expect(schemas.ZoneCreatePayload.required).toEqual(['name', 'type', 'geometry']);
    expect(schemas.ZoneCreatePayload.properties.type.enum)
      .toEqual(['house', 'crop_plot', 'livestock_area', 'water', 'storage', 'other']);
    expect(schemas.ZoneGeometry.required).toEqual(['points']);
    expect(schemas.ZoneGeometry.properties.points).toMatchObject({ minItems: 3 });
    expect(schemas.ZoneGeometry.properties.points.items.$ref).toBe('#/components/schemas/ZonePoint');
    expect(schemas.ZonePoint.properties.x.$ref).toBe('#/components/schemas/UnitInterval');
    expect(schemas.ZonePoint.properties.y.$ref).toBe('#/components/schemas/UnitInterval');
    expect(schemas.UnitInterval.pattern).toBeDefined();
    expect(schemas.AreaM2String.pattern).toBeDefined();
    expect(schemas.CropSpeciesCreatePayload.required).toEqual(['name', 'harvestUnit']);
    expect(schemas.CropSpeciesCreatePayload.properties.harvestUnit.enum).toEqual(['kg', 'litre', 'pieces']);
    expect(schemas.PlantingCreatePayload.required).toEqual(expect.arrayContaining(['cropSpeciesId', 'plotId', 'sowingDate']));
    expect(schemas.PlantingUpdatePayload.properties).not.toHaveProperty('cropSpeciesId');
    expect(schemas.PlantingUpdatePayload.properties).not.toHaveProperty('plotId');
    expect(schemas.HerdCreatePayload.required).toContain('mode');
    expect(schemas.HerdCreatePayload.properties.mode.enum).toEqual(['batch', 'tracked']);
    expect(schemas.AnimalCreatePayload.required).toEqual(['herdId', 'tag']);
    expect(schemas.AnimalCreatePayload.properties.status.enum).toEqual(['alive', 'sold', 'deceased']);
    expect(schemas.WaterTankCreatePayload.required).toEqual(expect.arrayContaining(['name', 'zoneId', 'capacityLitres']));
    for (const updatePayload of ['FarmUpdatePayload', 'ZoneUpdatePayload', 'CropSpeciesUpdatePayload', 'PlantingUpdatePayload', 'HerdUpdatePayload', 'AnimalUpdatePayload', 'WaterTankUpdatePayload']) {
      expect(schemas[updatePayload].minProperties).toBe(1);
      expect(schemas[updatePayload].additionalProperties).toBe(false);
      expect(schemas[updatePayload].required).toEqual([]);
    }

    expect(schemas.HerdDto.required).toContain('headcount');
    expect(schemas.HerdDto.properties.headcount).toMatchObject({ type: 'integer', minimum: 0 });
    expect(schemas.AnimalDto.required).toContain('archived');
    expect(schemas.ZoneDto.properties.geometry.$ref).toBe('#/components/schemas/ZoneGeometry');
    expect(schemas.FarmDto.required).toEqual(expect.arrayContaining(['farmId', 'name', 'timezone', 'status', 'version']));
    expect(schemas.FarmDirectoryEntry.required).toEqual(expect.arrayContaining(['farmId', 'farmName', 'status', 'grantRole']));
    expect(schemas.PlantingDto.required).toEqual(expect.arrayContaining(['cropSpeciesId', 'plotId']));

    const listCases = [
      [`${F}/zones`, 'ZoneListResponse', 'zones', 'ZoneDto'],
      [`${F}/crop-species`, 'CropSpeciesListResponse', 'cropSpecies', 'CropSpeciesDto'],
      [`${F}/plantings`, 'PlantingListResponse', 'plantings', 'PlantingDto'],
      [`${F}/herds`, 'HerdListResponse', 'herds', 'HerdDto'],
      [`${F}/animals`, 'AnimalListResponse', 'animals', 'AnimalDto'],
      [`${F}/water-tanks`, 'WaterTankListResponse', 'waterTanks', 'WaterTankDto'],
    ];
    for (const [path, response, listKey, dto] of listCases) {
      expect(successRef(path, 'get')).toBe(response);
      const dataRef = schemas[response].properties.data.$ref.split('/').at(-1);
      expect(schemas[dataRef].properties[listKey].items.$ref).toBe(`#/components/schemas/${dto}`);
      expect(schemas[response].properties.meta.$ref).toBe('#/components/schemas/ResponseMeta');
      expect(schemas[response].properties.page.$ref).toBe('#/components/schemas/PageInfo');
    }
    expect(schemas.DomainMutationResponse.properties.data.$ref).toBe('#/components/schemas/DomainMutationData');
    expect(schemas.DomainMutationResponse.properties.meta.$ref).toBe('#/components/schemas/ScopedResponseMeta');
    expect(schemas.ScopedResponseMeta.required).toEqual(['schemaVersion', 'asOf', 'scopePolicyVersion']);
    expect(schemas.ScopedResponseMeta.properties.scopePolicyVersion)
      .toEqual({ $ref: '#/components/schemas/PolicyVersion' });
    expect(schemas.DomainMutationData.additionalProperties).toBe(true);
    expect(schemas.DomainMutationData.required).toEqual(expect.arrayContaining(['operationId', 'outcome', 'revision']));
    expect(schemas.DomainMutationData.properties.outcome.enum)
      .toEqual(['applied', 'rejected', 'conflict', 'unknown']);
  });

  it('documents organization invitation requests, responses, and fixed expiry', () => {
    const schemas = openapi.components.schemas;
    const list = openapi.paths['/v1/organizations/{orgId}/invitations'].get;
    const create = openapi.paths['/v1/organizations/{orgId}/invitations'].post;
    const revoke = openapi.paths['/v1/organizations/{orgId}/invitations/{invitationId}/revoke'].post;
    const accept = openapi.paths['/v1/organizations/{orgId}/invitations/{invitationId}/accept'].post;
    const responseSchema = (operation, status) =>
      operation.responses[status].content['application/json'].schema.$ref;

    expect(responseSchema(list, '200')).toBe('#/components/schemas/OrganizationInvitationListResponse');
    expect(list.parameters.map((parameter) => parameter.name)).toEqual(expect.arrayContaining(['limit', 'cursor']));
    expect(create.requestBody.content['application/json'].schema.$ref)
      .toBe('#/components/schemas/CreateOrganizationInvitationRequest');
    expect(create.parameters).toContainEqual(expect.objectContaining({ name: 'Idempotency-Key', in: 'header', required: true }));
    expect(responseSchema(create, '201')).toBe('#/components/schemas/CreatedOrganizationInvitationResponse');
    expect(create.description).toContain('72 hours');
    expect(revoke.requestBody.content['application/json'].schema.$ref)
      .toBe('#/components/schemas/RevokeOrganizationInvitationRequest');
    expect(revoke.parameters).toContainEqual(expect.objectContaining({ name: 'Idempotency-Key', in: 'header', required: true }));
    expect(responseSchema(revoke, '201')).toBe('#/components/schemas/RevokedOrganizationInvitationResponse');
    expect(revoke.description).toContain('policyVersion increment');
    expect(accept.requestBody.content['application/json'].schema.$ref)
      .toBe('#/components/schemas/AcceptOrganizationInvitationRequest');
    expect(responseSchema(accept, '201')).toBe('#/components/schemas/AcceptedOrganizationInvitationResponse');

    expect(schemas.CreateOrganizationInvitationPayload.properties.farmGrants.maxItems).toBe(100);
    expect(schemas.AcceptOrganizationInvitationPayload.properties.token.pattern).toBe('^[a-f0-9]{64}$');
    expect(schemas.OrganizationInvitationView.properties.status.enum).toEqual(['pending', 'accepted', 'expired', 'revoked']);
    expect(schemas.OrganizationInvitationView.properties.acceptedAt.type).toEqual(['string', 'null']);
    expect(schemas.OrganizationInvitationView.properties.revokedAt.type).toEqual(['string', 'null']);
    expect(schemas.CreatedOrganizationInvitationData.properties.acceptanceToken.pattern).toBe('^[a-f0-9]{64}$');
    expect(schemas.CreatedOrganizationInvitationData.required).toContain('acceptanceToken');
    expect(schemas.AcceptedOrganizationInvitationData.properties.policyVersion.pattern).toBe('^[1-9][0-9]*$');
    expect(schemas.RevokedOrganizationInvitationData.properties.invitation.properties.status.const).toBe('revoked');
    expect(schemas.RevokedOrganizationInvitationData.properties.policyVersion.pattern).toBe('^[1-9][0-9]*$');
  });

  it('documents the owner/admin membership roster and exact write payloads', () => {
    const schemas = openapi.components.schemas;
    const list = openapi.paths['/v1/organizations/{orgId}/memberships'].get;
    const patch = openapi.paths['/v1/organizations/{orgId}/memberships/{membershipId}'].patch;
    const remove = openapi.paths['/v1/organizations/{orgId}/memberships/{membershipId}'].delete;
    const transfer = openapi.paths['/v1/organizations/{orgId}/ownership-transfers'].post;
    const responseSchema = (operation, status) =>
      operation.responses[status].content['application/json'].schema.$ref;

    expect(responseSchema(list, '200')).toBe('#/components/schemas/OrganizationMembershipListResponse');
    expect(list.parameters.map((parameter) => parameter.name)).toEqual(expect.arrayContaining(['limit', 'cursor']));
    expect(list.parameters.find((parameter) => parameter.name === 'cursor').schema)
      .toEqual({ $ref: '#/components/schemas/Uuid' });
    expect(schemas.OrganizationMembershipListResponse.properties.meta.$ref)
      .toBe('#/components/schemas/OrganizationMembershipListMeta');
    expect(schemas.OrganizationMembershipListMeta.required)
      .toEqual(['schemaVersion', 'asOf', 'scopePolicyVersion']);
    expect(schemas.OrganizationMembershipListMeta.properties.scopePolicyVersion)
      .toEqual({ $ref: '#/components/schemas/PolicyVersion' });
    expect(schemas.ResponseMeta.required).not.toContain('scopePolicyVersion');
    expect(schemas.OrganizationMembershipView.required).toEqual(
      expect.arrayContaining(['id', 'userId', 'role', 'status', 'version', 'farmGrants']),
    );
    expect(schemas.OrganizationMembershipView.properties).not.toHaveProperty('email');
    expect(schemas.OrganizationMembershipView.properties).not.toHaveProperty('displayName');
    expect(patch.requestBody.content['application/json'].schema.$ref)
      .toBe('#/components/schemas/PatchOrganizationMembershipRequest');
    expect(patch.parameters).toContainEqual(expect.objectContaining({ name: 'Idempotency-Key', in: 'header', required: true }));
    expect(schemas.PatchOrganizationMembershipPayload.properties.role.enum).toEqual(['admin', 'member', 'viewer']);
    expect(schemas.PatchOrganizationMembershipPayload.properties.farmGrants.maxItems).toBe(100);
    expect(responseSchema(patch, '200')).toBe('#/components/schemas/OrganizationMembershipMutationResponse');
    expect(responseSchema(remove, '200')).toBe('#/components/schemas/OrganizationMembershipMutationResponse');
    expect(transfer.requestBody.content['application/json'].schema.$ref)
      .toBe('#/components/schemas/TransferOrganizationOwnershipRequest');
    expect(transfer.parameters).toContainEqual(expect.objectContaining({ name: 'Idempotency-Key', in: 'header', required: true }));
    expect(responseSchema(transfer, '200')).toBe('#/components/schemas/OwnershipTransferResponse');
  });

  it('covers all normalized private AI events and keeps AI routes owner-private/read-only', () => {
    expect(openapi['x-farmly-ai-event-types']).toEqual([
      'request.started', 'response.delta', 'request.status', 'response.references',
      'usage.reported', 'response.completed', 'response.cancelled', 'response.error',
    ]);
    expect(openapi.components.schemas.AiEvent.properties.type.enum).toEqual(openapi['x-farmly-ai-event-types']);
    const privateAi = openapi['x-farmly-required-endpoints'].filter((entry) => entry.path.includes('/ai/'));
    expect(privateAi.length).toBeGreaterThan(0);
    for (const route of privateAi) {
      const operation = openapi.paths[route.path][route.method.toLowerCase()];
      expect(operation['x-farmly-private-owner-only']).toBe(true);
      expect(operation['x-farmly-ai-no-farm-mutation']).toBe(true);
    }
    expect(openapi.components.schemas.AiRequestStatus.properties.status.enum).toContain('interrupted');
  });

  it('regenerates OpenAPI and Dart types without drift', () => {
    expect(readFileSync(dartPath, 'utf8')).toContain('final class FarmlyDecimal');
    expect(readFileSync(dartPath, 'utf8')).not.toContain('double');
    expect(() => execFileSync(process.execPath, [generatorPath, '--check'], { cwd: ROOT, stdio: 'pipe' })).not.toThrow();
  });
});

describe('Q-BOOTSTRAP-SIZE fixture contract', () => {
  const fixtureText = readFileSync(fixturePath, 'utf8');

  it('covers every permitted farm bootstrap entity including water and task transitions', () => {
    const fixture = JSON.parse(fixtureText);
    expect(fixture.entityProfiles.map((profile) => profile.entity)).toEqual(bootstrapEntities);
    expect(bootstrapEntities).toContain('waterTanks');
    expect(bootstrapEntities).toContain('waterUsages');
    expect(bootstrapEntities).toContain('taskOccurrences');
    expect(bootstrapEntities).toContain('taskTransitions');
  });

  it('produces deterministic exact UTF-8 sizing, hashes, and an unapproved candidate', () => {
    const first = measureFixture(fixtureText, openapiText);
    const second = measureFixture(fixtureText, openapiText);
    expect(first).toEqual(second);
    expect(first.status).toBe('MEASURED_CANDIDATE_ONLY');
    expect(first.accepted).toBe(false);
    expect(first.candidateCaps.approved).toBe(false);
    expect(first.candidateCaps.ratificationOwner).toBe('product/operator owner');
    expect(first.candidateCaps.requiresOwnerRatificationBefore).toBe('P08');
    expect(first.rowsByEntity).toHaveLength(bootstrapEntities.length);
    expect(first.totalRows).toBe(first.rowsByEntity.reduce((sum, row) => sum + row.rows, 0));
    expect(first.manifest.utf8Bytes).toBeGreaterThan(0);
    expect(first.schemaSha256).toBe(first.openapiSha256);
    expect(first.serializerSha256).toMatch(/^[a-f0-9]{64}$/);
    expect(first.fixtureSha256).toMatch(/^[a-f0-9]{64}$/);
    expect(first.chunks.totalUtf8Bytes).toBe(first.chunks.frames.reduce((sum, chunk) => sum + chunk.utf8Bytes, 0));
    expect(first.totalTransferUtf8Bytes).toBe(first.manifest.utf8Bytes + first.chunks.totalUtf8Bytes);
    expect(first.candidateCaps.maxRows).toBeGreaterThan(first.totalRows);
    expect(first.candidateCaps.maxBytes).toBeGreaterThan(first.totalTransferUtf8Bytes);
  });

  it('fails closed on paths outside the declared fixture and receipt roots', () => {
    const outsideFixture = spawnSync(process.execPath, [sizingToolPath, '--fixture', 'README.md', '--output', `${PLAN_REPORTS}unsafe.json`], { cwd: ROOT, encoding: 'utf8' });
    expect(outsideFixture.status).toBe(2);
    expect(outsideFixture.stderr).toContain('FIXTURE_BOUNDARY');
    const outsideOutput = spawnSync(process.execPath, [sizingToolPath, '--fixture', 'tools/qa/fixtures/bootstrap-supported-v1.json', '--output', 'apps/api/unsafe.json'], { cwd: ROOT, encoding: 'utf8' });
    expect(outsideOutput.status).toBe(2);
    expect(outsideOutput.stderr).toContain('OUTPUT_BOUNDARY');
  });
});
