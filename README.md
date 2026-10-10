# Farmly

Farmly is a Flutter Android/iOS client and NestJS API for multi-organization farm operations. The repository is in its foundation phase; device, database-integration, provider, and release checks remain separate gates.

## Local service configuration

`infra/compose.yaml` defines a dedicated `farmly_test_261005` PostgreSQL database and Mailpit instance. Both services use exact image tags, loopback-only host ports, and an isolated Docker network. The Compose project and data volume are named for this Farmly test scope.

To prepare a local environment, copy `infra/.env.example` to `infra/.env` and replace all placeholder passwords with unique local-only values. The bootstrap, auth, tenant, and migration roles are separate; keep the migration URL in the migration process only. Validate the configuration without starting containers:

```powershell
docker compose -f infra/compose.yaml --env-file infra/.env config --quiet
```

No container or database is started by repository checks. Keep migration credentials in the migration process only; the API runtime rejects `MIGRATION_DATABASE_URL`. Do not use Compose cleanup options that remove volumes when preserving local test data.

## Verification commands

```powershell
npm --prefix apps/api run build
npm --prefix apps/api run test:unit
node contracts/scripts/build-contracts.mjs --check
node tools/qa/check-dependency-pins.mjs --json
node tools/qa/check-secrets.mjs --scope source-and-bundles --json
node tools/qa/preflight.mjs --json
```

`BLOCKED_CAPABILITY` and `NOT_RUN` results indicate missing live prerequisites; they are not product passes. See [`plans/261005-1435-farmly-mobile-app/plan.md`](plans/261005-1435-farmly-mobile-app/plan.md) for scope, evidence, and current gates.
