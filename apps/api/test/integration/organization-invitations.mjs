import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { Client } from 'pg';

const expectedDatabaseName = 'farmly_test_261005';
const migrationUrl = process.env.MIGRATION_DATABASE_URL;
const tenantPassword = process.env.FARMLY_TEST_TENANT_PASSWORD;
const configuredDatabaseName = process.env.FARMLY_TEST_DATABASE_NAME;
let currentStage = 'startup';

function assert(condition, code) {
  if (condition) return;
  const error = new Error(code);
  error.code = code;
  throw error;
}

function hash(value) {
  return createHash('sha256').update(value).digest('hex');
}

function assertTarget(url, username) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    assert(false, 'DATABASE_URL_INVALID');
  }
  assert(parsed.hostname === 'postgres', 'DATABASE_HOST_INVALID');
  assert(decodeURIComponent(parsed.pathname.slice(1)) === expectedDatabaseName, 'DATABASE_NAME_INVALID');
  if (username) assert(decodeURIComponent(parsed.username) === username, 'DATABASE_ROLE_INVALID');
}

function invitationToken() {
  return randomBytes(32).toString('hex');
}

function tenantConnectionString(applicationName) {
  assert(tenantPassword, 'TENANT_ROLE_PASSWORD_REQUIRED');
  const encodedPassword = encodeURIComponent(tenantPassword);
  const encodedApplicationName = encodeURIComponent(applicationName);
  return `postgresql://farmly_tenant_app:${encodedPassword}@postgres:5432/${expectedDatabaseName}?application_name=${encodedApplicationName}`;
}

function withApplicationName(connectionString, applicationName) {
  const url = new URL(connectionString);
  url.searchParams.set('application_name', applicationName);
  return url.toString();
}

async function waitForLockWaits(migration, applicationNames, lockHolderPid) {
  for (let attempt = 0; attempt < 250; attempt += 1) {
    const activity = await migration.query(`
      SELECT waiting.application_name,
             waiting.wait_event_type,
             waiting.wait_event,
             pg_catalog.pg_blocking_pids(waiting.pid) AS blocking_pids,
             $2::INTEGER = ANY(pg_catalog.pg_blocking_pids(waiting.pid)) AS blocked_by_lock_holder,
             EXISTS (
               SELECT 1
                 FROM unnest(pg_catalog.pg_blocking_pids(waiting.pid)) AS blocker(pid)
                 JOIN pg_catalog.pg_stat_activity AS blocker_activity
                   ON blocker_activity.pid = blocker.pid
                WHERE blocker_activity.application_name = ANY($1::text[])
                  AND blocker_activity.application_name <> waiting.application_name
             ) AS blocked_by_invitation_waiter
        FROM pg_catalog.pg_stat_activity AS waiting
       WHERE waiting.application_name = ANY($1::text[])
    `, [applicationNames, lockHolderPid]);
    const activityByName = new Map(activity.rows.map((row) => [row.application_name, row]));
    const allWaitersBlockedOnLockChain = applicationNames.every((name) => {
      const row = activityByName.get(name);
      return Array.isArray(row?.blocking_pids)
        && row.blocking_pids.length > 0
        && (row.blocked_by_lock_holder === true || row.blocked_by_invitation_waiter === true);
    });
    const lockHolderBlocksChain = activity.rows.some((row) => row.blocked_by_lock_holder === true);
    if (allWaitersBlockedOnLockChain && lockHolderBlocksChain) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  const finalActivity = await migration.query(`
    SELECT waiting.application_name,
           waiting.wait_event_type,
           waiting.wait_event,
           pg_catalog.pg_blocking_pids(waiting.pid) AS blocking_pids,
           $2::INTEGER = ANY(pg_catalog.pg_blocking_pids(waiting.pid)) AS blocked_by_lock_holder,
           EXISTS (
             SELECT 1
               FROM unnest(pg_catalog.pg_blocking_pids(waiting.pid)) AS blocker(pid)
               JOIN pg_catalog.pg_stat_activity AS blocker_activity
                 ON blocker_activity.pid = blocker.pid
              WHERE blocker_activity.application_name = ANY($1::text[])
                AND blocker_activity.application_name <> waiting.application_name
           ) AS blocked_by_invitation_waiter
      FROM pg_catalog.pg_stat_activity AS waiting
     WHERE waiting.application_name = ANY($1::text[])
  `, [applicationNames, lockHolderPid]);
  const diagnostics = applicationNames.map((applicationName) => {
    const row = finalActivity.rows.find((activityRow) => activityRow.application_name === applicationName);
    return {
      present: Boolean(row),
      waitEventType: row?.wait_event_type ?? null,
      waitEvent: row?.wait_event ?? null,
      blockerCount: Array.isArray(row?.blocking_pids) ? row.blocking_pids.length : 0,
      blockedByLockHolder: row?.blocked_by_lock_holder === true,
      blockedByInvitationWaiter: row?.blocked_by_invitation_waiter === true,
    };
  });
  throw Object.assign(new Error('INVITATION_ACCEPT_LOCK_WAIT_NOT_OBSERVED'), {
    code: 'INVITATION_ACCEPT_LOCK_WAIT_NOT_OBSERVED',
    diagnostics,
  });
}

async function withActor(client, actorId, operation) {
  await client.query('BEGIN');
  try {
    await client.query("SELECT set_config('app.actor_id', $1, TRUE)", [actorId]);
    const result = await operation(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function expectCode(operation, expectedCode, failureCode) {
  let caught;
  try {
    await operation();
  } catch (error) {
    caught = error;
  }
  assert(caught?.code === expectedCode, failureCode);
}

function verifiedPrincipal(user) {
  return {
    actorId: user.id,
    email: user.email,
    displayName: 'Invitation test user',
    sessionId: randomUUID(),
    sessionExpiresAt: new Date(Date.now() + 60_000),
  };
}

async function expectServiceCode(operation, expectedStatus, expectedCode, failureCode) {
  let caught;
  try {
    await operation();
  } catch (error) {
    caught = error;
  }
  const response = caught && typeof caught.getResponse === 'function' ? caught.getResponse() : null;
  assert(caught?.getStatus?.() === expectedStatus && response?.code === expectedCode, failureCode);
}

async function insertVerifiedUsers(migration, users) {
  const values = [];
  const rows = users.map(({ id, email, verified = true }, index) => {
    const offset = index * 4;
    values.push(id, email, verified, new Date());
    return `($${offset + 1}, 'Invitation test user', $${offset + 2}, $${offset + 3}, $${offset + 4})`;
  });
  await migration.query(`
    INSERT INTO auth."user" (id, name, email, "emailVerified", "updatedAt")
    VALUES ${rows.join(', ')}
  `, values);
}

async function createOrganization(migration, actorId, name) {
  await migration.query('BEGIN');
  try {
    await migration.query("SELECT set_config('app.actor_id', $1, TRUE)", [actorId]);
    const result = await migration.query(
      'SELECT * FROM public.create_organization_for_verified_principal($1, $2::uuid, $3)',
      [actorId, randomUUID(), name],
    );
    await migration.query('COMMIT');
    return result.rows[0].organization_id;
  } catch (error) {
    await migration.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function createInvitation(app, actorId, values) {
  return withActor(app, actorId, (client) => client.query(`
    SELECT * FROM public.create_organization_invitation(
      $1::uuid, $2::uuid, $3, $4::public.organization_role, $5, $6::jsonb
    )
  `, values));
}

async function acceptInvitation(app, actorId, values) {
  return withActor(app, actorId, (client) => client.query(`
    SELECT * FROM public.accept_organization_invitation(
      $1::uuid, $2::uuid, $3, $4, $5::uuid
    )
  `, values));
}

async function main() {
  assert(migrationUrl && configuredDatabaseName === expectedDatabaseName, 'MIGRATION_DATABASE_CONFIGURATION_INVALID');
  assertTarget(migrationUrl, 'farmly_migration');

  const suffix = randomUUID();
  const appNameA = `farmly-invite-a-${suffix}`;
  const appNameB = `farmly-invite-b-${suffix}`;
  const serviceAppName = `farmly-invite-service-${suffix}`;
  const lockHolderAppName = `farmly-invite-lock-${suffix}`;
  const migration = new Client({ connectionString: withApplicationName(migrationUrl, lockHolderAppName) });
  const appA = new Client({ connectionString: tenantConnectionString(appNameA) });
  const appB = new Client({ connectionString: tenantConnectionString(appNameB) });
  let tenantDatabaseService = null;
  let invitationsService = null;
  const users = [
    { id: `invite-owner-${suffix}`, email: `owner-${suffix}@farmly.test` },
    { id: `invite-admin-${suffix}`, email: `admin-${suffix}@farmly.test` },
    { id: `invite-member-${suffix}`, email: `member-${suffix}@farmly.test` },
    { id: `invitee-${suffix}`, email: `invitee-${suffix}@farmly.test` },
    { id: `invitee-second-${suffix}`, email: `invitee-second-${suffix}@farmly.test` },
    { id: `invitee-wrong-${suffix}`, email: `wrong-${suffix}@farmly.test` },
    { id: `invitee-unverified-${suffix}`, email: `unverified-${suffix}@farmly.test`, verified: false },
    { id: `invite-owner-other-${suffix}`, email: `owner-other-${suffix}@farmly.test` },
  ];
  const organizationIds = [];
  let cleanupError = null;
  let cleanupStage = null;
  let operationError = null;
  let operationStage = null;

  try {
    currentStage = 'connect-and-load-service';
    await Promise.all([migration.connect(), appA.connect(), appB.connect()]);
    const [{ TenantDatabaseService }, { OrganizationInvitationsService }] = await Promise.all([
      import(new URL('../../dist/db/tenant-database.service.js', import.meta.url)),
      import(new URL('../../dist/organizations/organization-invitations.service.js', import.meta.url)),
    ]);
    tenantDatabaseService = new TenantDatabaseService({
      get: (key) => key === 'farmlyEnvironment'
        ? { databaseUrlTenant: tenantConnectionString(serviceAppName) }
        : undefined,
    });
    await tenantDatabaseService.onModuleInit();
    invitationsService = new OrganizationInvitationsService(tenantDatabaseService);
    const identity = await migration.query('SELECT current_user AS role, current_database() AS database');
    assert(identity.rows[0]?.role === 'farmly_migration' && identity.rows[0]?.database === expectedDatabaseName, 'MIGRATION_DATABASE_IDENTITY_INVALID');

    const migrationReady = await migration.query(`
      SELECT to_regprocedure('public.create_organization_invitation(uuid,uuid,text,public.organization_role,text,jsonb)') IS NOT NULL AS ready,
             to_regprocedure('public.revoke_organization_invitation(uuid,uuid,uuid)') IS NOT NULL AS revoke_ready,
             EXISTS (SELECT 1 FROM public._farmly_migrations WHERE id = '202610060005_invitation_policy_version_qualification') AS policy_version_fix_ready,
             EXISTS (SELECT 1 FROM public._farmly_migrations WHERE id = '202610060006_invitation_ttl_after_org_lock') AS ttl_lock_fix_ready,
             EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = 'organizations'
                        AND column_name = 'continuity_epoch') AS epoch_ready
    `);
    assert(
      migrationReady.rows[0]?.ready
        && migrationReady.rows[0]?.revoke_ready
        && migrationReady.rows[0]?.policy_version_fix_ready
        && migrationReady.rows[0]?.ttl_lock_fix_ready
        && migrationReady.rows[0]?.epoch_ready,
      'ORGANIZATION_CONTROLS_MIGRATION_REQUIRED',
    );

    currentStage = 'seed-fixtures';
    await insertVerifiedUsers(migration, users);
    currentStage = 'create-organizations';
    const organizationA = await createOrganization(migration, users[0].id, `Invite Org A ${suffix}`);
    organizationIds.push(organizationA);
    const organizationB = await createOrganization(migration, users[7].id, `Invite Org B ${suffix}`);
    organizationIds.push(organizationB);
    const farmA = randomUUID();
    const farmB = randomUUID();
    currentStage = 'create-farms-and-members';
    await migration.query(`
      INSERT INTO public.farms (id, organization_id, name, timezone)
      VALUES ($1::uuid, $2::uuid, 'Invitation Farm A', 'Asia/Ho_Chi_Minh'),
             ($3::uuid, $4::uuid, 'Invitation Farm B', 'Asia/Ho_Chi_Minh')
    `, [farmA, organizationA, farmB, organizationB]);
    await migration.query(`
      INSERT INTO public.organization_memberships (organization_id, user_id, role, status)
      VALUES ($1::uuid, $2, 'admin', 'active'),
             ($1::uuid, $3, 'member', 'active')
    `, [organizationA, users[1].id, users[2].id]);

    const invitationOperationId = randomUUID();
    const normalizedEmail = users[3].email.normalize('NFKC').toLowerCase();
    const grantRows = [{ farmId: farmA, role: 'manager' }];
    currentStage = 'service-create-invitation';
    const created = await invitationsService.createFor(verifiedPrincipal(users[0]), organizationA, {
      operationId: invitationOperationId,
      email: users[3].email,
      role: 'member',
      farmGrants: grantRows,
    });
    assert(created.data.invitation.status === 'pending' && created.data.invitation.role === 'member', 'INVITATION_CREATE_FAILED');
    const invitationId = created.data.invitation.id;
    const invitationTokenValue = created.data.acceptanceToken;
    const expiryDelta = new Date(created.data.invitation.expiresAt).getTime()
      - new Date(created.data.invitation.createdAt).getTime();
    assert(expiryDelta === 72 * 60 * 60 * 1000, 'INVITATION_TTL_NOT_72_HOURS');

    currentStage = 'verify-digest-and-list';
    const stored = await migration.query(`
      SELECT email_hash, token_hash FROM public.organization_invitations
       WHERE organization_id = $1::uuid AND id = $2::uuid
    `, [organizationA, invitationId]);
    assert(stored.rowCount === 1 && stored.rows[0].email_hash.trim() === hash(normalizedEmail), 'INVITATION_EMAIL_HASH_NOT_STORED');
    assert(stored.rows[0].token_hash.trim() === hash(invitationTokenValue) && !stored.rows[0].token_hash.includes(invitationTokenValue), 'INVITATION_TOKEN_NOT_DIGEST_ONLY');

    const listed = await invitationsService.listFor(verifiedPrincipal(users[0]), organizationA, 25, null);
    assert(listed.data.invitations.length === 1 && listed.data.invitations[0].status === 'pending', 'INVITATION_LIST_FAILED');
    assert(!('email_hash' in listed.data.invitations[0]) && !('token_hash' in listed.data.invitations[0]), 'INVITATION_LIST_EXPOSED_DIGESTS');

    currentStage = 'verify-ttl-after-organization-lock';
    const delayedToken = invitationToken();
    let delayedCreateOutcome = null;
    let ttlLockTransactionOpen = false;
    try {
      await migration.query('BEGIN');
      ttlLockTransactionOpen = true;
      await migration.query('SELECT id FROM public.organizations WHERE id = $1::uuid FOR UPDATE', [organizationA]);
      const ttlLockHolder = await migration.query('SELECT pg_catalog.pg_backend_pid() AS pid');
      const delayedCreateOperation = createInvitation(appA, users[0].id, [
        organizationA,
        randomUUID(),
        hash(`delayed-${suffix}@farmly.test`),
        'member',
        hash(delayedToken),
        '[]',
      ]).then((value) => ({ value }), (error) => ({ error }));
      await waitForLockWaits(migration, [appNameA], Number(ttlLockHolder.rows[0]?.pid));
      const lockRelease = await migration.query('SELECT clock_timestamp() AS released_at');
      await migration.query('COMMIT');
      ttlLockTransactionOpen = false;
      delayedCreateOutcome = await delayedCreateOperation;
      assert(!delayedCreateOutcome.error, 'LOCKED_INVITATION_CREATE_FAILED');
      const delayedInvitation = delayedCreateOutcome.value.rows[0];
      assert(delayedInvitation, 'LOCKED_INVITATION_CREATE_EMPTY');
      assert(
        delayedInvitation.created_at.getTime() >= lockRelease.rows[0].released_at.getTime(),
        'INVITATION_TTL_STARTED_BEFORE_LOCK_RELEASE',
      );
      assert(
        delayedInvitation.expires_at.getTime() - delayedInvitation.created_at.getTime() === 72 * 60 * 60 * 1000,
        'INVITATION_TTL_NOT_72_HOURS_AFTER_LOCK_WAIT',
      );
    } finally {
      if (ttlLockTransactionOpen) await migration.query('ROLLBACK').catch(() => {});
    }

    currentStage = 'verify-least-privilege-access';
    await expectCode(
      () => withActor(appA, users[0].id, (client) => client.query(
        'SELECT * FROM public.organization_invitations WHERE id = $1::uuid', [invitationId],
      )),
      '42501',
      'TENANT_ROLE_READS_INVITATION_TABLE',
    );
    await expectCode(
      () => withActor(appB, users[2].id, (client) => client.query(
        'SELECT * FROM public.list_organization_invitations($1::uuid, 25, NULL)', [organizationA],
      )),
      '42501',
      'MEMBER_LISTED_ORGANIZATION_INVITATIONS',
    );

    currentStage = 'verify-unauthorized-service-operation';
    await expectServiceCode(
      () => invitationsService.createFor(verifiedPrincipal(users[2]), organizationA, {
        operationId: randomUUID(),
        email: 'unauthorized-target@farmly.test',
        role: 'member',
        farmGrants: [],
      }),
      403,
      'PERMISSION_DENIED',
      'MEMBER_CREATED_INVITATION',
    );
    await expectCode(
      () => createInvitation(appA, users[1].id, [organizationA, randomUUID(), hash('admin-target'), 'owner', hash(randomUUID()), '[]']),
      '22023',
      'OWNER_ROLE_INVITATION_ACCEPTED',
    );
    await expectCode(
      () => createInvitation(appA, users[0].id, [organizationA, randomUUID(), hash('viewer-target'), 'viewer', hash(randomUUID()), JSON.stringify([{ farmId: farmA, role: 'manager' }])]),
      '22023',
      'VIEWER_RECEIVED_WRITE_GRANT',
    );
    await expectCode(
      () => createInvitation(appA, users[0].id, [organizationA, randomUUID(), hash('cross-org-target'), 'member', hash(randomUUID()), JSON.stringify([{ farmId: farmB, role: 'worker' }])]),
      '22023',
      'CROSS_ORGANIZATION_INVITATION_GRANT_ACCEPTED',
    );
    await expectCode(
      () => createInvitation(appA, users[0].id, [organizationA, invitationOperationId, hash('different-target'), 'member', hash(randomUUID()), '[]']),
      '23505',
      'INVITATION_OPERATION_REPLAY_ACCEPTED',
    );

    currentStage = 'verify-acceptance-denials';
    const invitationEmailHash = hash(normalizedEmail);
    const invitationTokenHash = hash(invitationTokenValue);
    const acceptOperationId = randomUUID();
    const acceptValues = [organizationA, invitationId, invitationEmailHash, invitationTokenHash, acceptOperationId];
    await expectServiceCode(
      () => invitationsService.acceptFor(verifiedPrincipal(users[5]), organizationA, invitationId, randomUUID(), invitationTokenValue),
      403,
      'INVITATION_EMAIL_MISMATCH',
      'MISMATCHED_VERIFIED_EMAIL_ACCEPTED',
    );
    await expectServiceCode(
      () => invitationsService.acceptFor(verifiedPrincipal(users[6]), organizationA, invitationId, randomUUID(), invitationTokenValue),
      403,
      'PERMISSION_DENIED',
      'UNVERIFIED_PRINCIPAL_ACCEPTED_INVITATION',
    );
    await expectServiceCode(
      () => invitationsService.acceptFor(verifiedPrincipal(users[3]), organizationA, invitationId, randomUUID(), invitationToken()),
      404,
      'INVITATION_NOT_AVAILABLE',
      'INVALID_INVITATION_TOKEN_ACCEPTED',
    );

    currentStage = 'accept-invitation';
    const accepted = await invitationsService.acceptFor(
      verifiedPrincipal(users[3]),
      organizationA,
      invitationId,
      acceptOperationId,
      invitationTokenValue,
    );
    currentStage = 'verify-accepted-membership-and-grant';
    assert(accepted.data.membership.role === 'member' && accepted.data.replayed === false, 'INVITATION_ACCEPT_FAILED');
    const acceptedMembershipId = accepted.data.membership.id;
    const membership = await migration.query(`
      SELECT role, status, version FROM public.organization_memberships
       WHERE organization_id = $1::uuid AND id = $2::uuid
    `, [organizationA, acceptedMembershipId]);
    assert(membership.rowCount === 1 && membership.rows[0].role === 'member' && membership.rows[0].status === 'active', 'INVITED_MEMBERSHIP_NOT_CREATED');
    const grant = await migration.query(`
      SELECT farm_id, role FROM public.farm_grants
       WHERE organization_id = $1::uuid AND membership_id = $2::uuid
    `, [organizationA, acceptedMembershipId]);
    assert(grant.rowCount === 1 && grant.rows[0].farm_id === farmA && grant.rows[0].role === 'manager', 'INVITATION_GRANT_NOT_APPLIED');
    assert(accepted.data.policyVersion === '2', 'INVITATION_DID_NOT_ADVANCE_POLICY_VERSION');
    currentStage = 'verify-accepted-status-and-revoke-denial';
    const acceptedList = await invitationsService.listFor(verifiedPrincipal(users[0]), organizationA, 25, null);
    const acceptedView = acceptedList.data.invitations.find((invitation) => invitation.id === invitationId);
    assert(acceptedView?.status === 'accepted' && acceptedView.acceptedAt, 'ACCEPTED_INVITATION_STATUS_NOT_LISTED');
    await expectServiceCode(
      () => invitationsService.revokeFor(verifiedPrincipal(users[0]), organizationA, invitationId, randomUUID()),
      409,
      'INVITATION_ALREADY_ACCEPTED',
      'ACCEPTED_INVITATION_REVOKED',
    );

    currentStage = 'verify-accept-replay-policy-version';
    const replayA = await acceptInvitation(appA, users[3].id, acceptValues);
    const replayB = await acceptInvitation(appB, users[3].id, acceptValues);
    assert(replayA.rows[0]?.replayed === true && replayB.rows[0]?.replayed === true, 'INVITATION_ACCEPT_REPLAY_NOT_IDEMPOTENT');
    await expectCode(
      () => acceptInvitation(appA, users[3].id, [...acceptValues.slice(0, 4), randomUUID()]),
      'P0001',
      'INVITATION_SECOND_OPERATION_ACCEPTED',
    );
    const afterReplay = await migration.query('SELECT policy_version FROM public.organizations WHERE id = $1::uuid', [organizationA]);
    assert(afterReplay.rows[0]?.policy_version === '2', 'INVITATION_REPLAY_CHANGED_POLICY_VERSION');

    currentStage = 'verify-concurrent-accept';
    const concurrentToken = invitationToken();
    const concurrentInvitation = await createInvitation(appA, users[0].id, [
      organizationA, randomUUID(), hash(users[4].email), 'member', hash(concurrentToken), '[]',
    ]);
    const concurrentInvitationId = concurrentInvitation.rows[0].invitation_id;
    const concurrentAcceptValues = [
      organizationA,
      concurrentInvitationId,
      hash(users[4].email),
      hash(concurrentToken),
    ];
    let concurrentOperations = [];
    let lockWaitFailure = null;
    let organizationLockTransactionOpen = false;
    try {
      await migration.query('BEGIN');
      organizationLockTransactionOpen = true;
      await migration.query('SELECT id FROM public.organizations WHERE id = $1::uuid FOR UPDATE', [organizationA]);
      const lockHolder = await migration.query('SELECT pg_catalog.pg_backend_pid() AS pid');
      concurrentOperations = [
        acceptInvitation(appA, users[4].id, [...concurrentAcceptValues, randomUUID()])
          .then((result) => ({ status: 'accepted', result }), (error) => ({ status: 'rejected', code: error.code })),
        acceptInvitation(appB, users[4].id, [...concurrentAcceptValues, randomUUID()])
          .then((result) => ({ status: 'accepted', result }), (error) => ({ status: 'rejected', code: error.code })),
      ];
      try {
        await waitForLockWaits(migration, [appNameA, appNameB], Number(lockHolder.rows[0]?.pid));
        await migration.query('SAVEPOINT invitation_lock_order_probe');
        let invitationProbeError = null;
        let invitationProbeRows = null;
        try {
          invitationProbeRows = await migration.query(`
            SELECT id FROM public.organization_invitations
             WHERE organization_id = $1::uuid AND id = $2::uuid
             FOR UPDATE NOWAIT
          `, [organizationA, concurrentInvitationId]);
        } catch (error) {
          invitationProbeError = error;
        }
        await migration.query('ROLLBACK TO SAVEPOINT invitation_lock_order_probe');
        assert(
          !invitationProbeError && invitationProbeRows?.rowCount === 1,
          'INVITATION_LOCK_ACQUIRED_BEFORE_ORGANIZATION_LOCK',
        );
      } catch (error) {
        lockWaitFailure = error;
      }
      await migration.query(lockWaitFailure ? 'ROLLBACK' : 'COMMIT');
      organizationLockTransactionOpen = false;
    } finally {
      if (organizationLockTransactionOpen) await migration.query('ROLLBACK').catch(() => {});
    }
    const concurrentResults = await Promise.all(concurrentOperations);
    if (lockWaitFailure) throw lockWaitFailure;
    const concurrentWinners = concurrentResults.filter((result) => result.status === 'accepted');
    const concurrentLosers = concurrentResults.filter((result) => result.status === 'rejected');
    assert(
      concurrentWinners.length === 1
        && concurrentWinners[0].result.rows[0]?.replayed === false
        && concurrentLosers.length === 1
        && concurrentLosers[0].code === 'P0001',
      'CONCURRENT_INVITATION_ACCEPT_NOT_SINGLE_WINNER',
    );
    const concurrentMembership = await migration.query(`
      SELECT count(*)::INTEGER AS count
        FROM public.organization_memberships
       WHERE organization_id = $1::uuid AND user_id = $2 AND status = 'active'
    `, [organizationA, users[4].id]);
    assert(concurrentMembership.rows[0]?.count === 1, 'CONCURRENT_INVITATION_CREATED_MULTIPLE_MEMBERSHIPS');
    const afterConcurrentAccept = await migration.query(
      'SELECT policy_version FROM public.organizations WHERE id = $1::uuid',
      [organizationA],
    );
    assert(afterConcurrentAccept.rows[0]?.policy_version === '3', 'CONCURRENT_ACCEPT_CHANGED_POLICY_VERSION_MORE_THAN_ONCE');

    currentStage = 'verify-expired-invitation';
    const expiredOperation = randomUUID();
    const expiredToken = invitationToken();
    const expiredCreate = await createInvitation(appA, users[0].id, [
      organizationA, expiredOperation, hash(users[4].email), 'member', hash(expiredToken), '[]',
    ]);
    const expiredId = expiredCreate.rows[0].invitation_id;
    await migration.query(
      "UPDATE public.organization_invitations SET expires_at = created_at + INTERVAL '1 microsecond' WHERE id = $1::uuid",
      [expiredId],
    );
    const expiredList = await invitationsService.listFor(verifiedPrincipal(users[0]), organizationA, 25, null);
    const expiredView = expiredList.data.invitations.find((invitation) => invitation.id === expiredId);
    assert(expiredView?.status === 'expired', 'EXPIRED_INVITATION_STATUS_NOT_LISTED');
    await expectServiceCode(
      () => invitationsService.acceptFor(verifiedPrincipal(users[4]), organizationA, expiredId, randomUUID(), expiredToken),
      410,
      'INVITATION_EXPIRED',
      'EXPIRED_INVITATION_ACCEPTED',
    );

    currentStage = 'verify-revoked-invitation';
    const revokedOperation = randomUUID();
    const revokedToken = invitationToken();
    const revokedCreate = await createInvitation(appA, users[0].id, [
      organizationA, revokedOperation, hash(users[4].email), 'member', hash(revokedToken), '[]',
    ]);
    const revokedId = revokedCreate.rows[0].invitation_id;
    const revokeOperationId = randomUUID();
    const revoked = await invitationsService.revokeFor(
      verifiedPrincipal(users[0]),
      organizationA,
      revokedId,
      revokeOperationId,
    );
    assert(revoked.data.invitation.status === 'revoked' && revoked.data.replayed === false, 'INVITATION_REVOKE_FAILED');
    const revokedReplay = await invitationsService.revokeFor(
      verifiedPrincipal(users[0]),
      organizationA,
      revokedId,
      revokeOperationId,
    );
    assert(revokedReplay.data.replayed === true && revokedReplay.data.policyVersion === '4', 'INVITATION_REVOKE_REPLAY_CHANGED_POLICY');
    await expectServiceCode(
      () => invitationsService.revokeFor(verifiedPrincipal(users[0]), organizationA, revokedId, randomUUID()),
      410,
      'INVITATION_REVOKED',
      'INVITATION_REVOKE_ACCEPTED_NEW_OPERATION',
    );
    await expectServiceCode(
      () => invitationsService.acceptFor(verifiedPrincipal(users[4]), organizationA, revokedId, randomUUID(), revokedToken),
      410,
      'INVITATION_REVOKED',
      'REVOKED_INVITATION_ACCEPTED',
    );
    const revokedList = await invitationsService.listFor(verifiedPrincipal(users[0]), organizationA, 25, null);
    const revokedView = revokedList.data.invitations.find((invitation) => invitation.id === revokedId);
    assert(revokedView?.status === 'revoked' && revokedView.revokedAt, 'REVOKED_INVITATION_STATUS_NOT_LISTED');

    console.log('PASS organization invitation PostgreSQL/service cases: fixed 72h TTL, digest-only token, verified principal email binding, least-privilege access, observed lock-holder blocking, single-winner accept, accept/revoke replay, grant scope, expiry, revoke.');
  } catch (error) {
    operationError = error;
    operationStage = currentStage;
  } finally {
    if (migration._connected) {
      try {
        currentStage = 'cleanup-organizations';
        await migration.query(`
          DELETE FROM public.organizations
           WHERE id = ANY($1::uuid[])
              OR id IN (
                    SELECT membership.organization_id
                      FROM public.organization_memberships AS membership
                     WHERE membership.user_id = ANY($2::text[])
                       AND membership.role = 'owner'
                )
        `, [organizationIds, [users[0].id, users[7].id]]);
        currentStage = 'cleanup-users';
        await migration.query('DELETE FROM auth."user" WHERE id = ANY($1::text[])', [users.map((user) => user.id)]);
        currentStage = 'verify-fixture-cleanup';
        const remainingFixtures = await migration.query(`
          SELECT
            (SELECT count(*)::INTEGER FROM public.organizations AS organization
              WHERE organization.id = ANY($1::uuid[])
                 OR organization.id IN (
                      SELECT membership.organization_id
                        FROM public.organization_memberships AS membership
                       WHERE membership.user_id = ANY($2::text[])
                         AND membership.role = 'owner'
                 )) AS organizations,
            (SELECT count(*)::INTEGER FROM auth."user" WHERE id = ANY($3::text[])) AS users
        `, [organizationIds, [users[0].id, users[7].id], users.map((user) => user.id)]);
        assert(
          remainingFixtures.rows[0]?.organizations === 0 && remainingFixtures.rows[0]?.users === 0,
          'ORGANIZATION_INVITATION_FIXTURES_REMAIN',
        );
      } catch (error) {
        cleanupError = error;
        cleanupStage = currentStage;
      }
    }
    await tenantDatabaseService?.onModuleDestroy().catch(() => {});
    await Promise.all([migration.end(), appA.end(), appB.end()].map((promise) => promise.catch(() => {})));
  }

  if (cleanupError) {
    throw Object.assign(new Error('ORGANIZATION_INVITATION_CLEANUP_FAILED'), {
      code: 'ORGANIZATION_INVITATION_CLEANUP_FAILED',
      operationError,
      operationStage,
      cleanupError,
      cleanupStage,
    });
  }
  if (operationError) {
    const failure = operationError instanceof Error ? operationError : new Error('UNEXPECTED');
    throw Object.assign(failure, { operationStage });
  }
}

main().catch((error) => {
  const operationFailure = error?.operationError ?? error;
  const code = typeof operationFailure?.code === 'string' ? operationFailure.code : 'UNEXPECTED';
  const nestedSqlState = operationFailure?.meta?.driverAdapterError?.cause?.code;
  const safeSqlState = typeof nestedSqlState === 'string' && /^[0-9A-Z]{5}$/.test(nestedSqlState) ? nestedSqlState : null;
  const operationStage = error?.operationStage ?? error?.stage ?? currentStage;
  const safeAdapterDetail = safeSqlState ? ` sqlstate=${safeSqlState}` : '';
  const cleanupCode = typeof error?.cleanupError?.code === 'string' ? error.cleanupError.code : null;
  const cleanupSqlState = error?.cleanupError?.meta?.driverAdapterError?.cause?.code;
  const safeCleanupSqlState = typeof cleanupSqlState === 'string' && /^[0-9A-Z]{5}$/.test(cleanupSqlState)
    ? cleanupSqlState
    : null;
  const cleanupDetail = cleanupCode
    ? ` cleanup=${error.cleanupStage}:${cleanupCode}${safeCleanupSqlState ? ` sqlstate=${safeCleanupSqlState}` : ''}`
    : '';
  const lockWaitDetail = Array.isArray(operationFailure?.diagnostics)
    ? ` locks=${JSON.stringify(operationFailure.diagnostics)}`
    : '';
  console.error(`ORGANIZATION_INVITATIONS_FAILED: stage=${operationStage} code=${code}${safeAdapterDetail}${cleanupDetail}${lockWaitDetail}`);
  process.exitCode = 1;
});
