# Farmly

**Offline-first farm operations platform** — a Flutter mobile app backed by a
multi-tenant NestJS + PostgreSQL API. Farmly lets cooperatives manage crops,
livestock, water, tasks and harvests across organizations and farms — in the
field, with or without connectivity.

<p align="center">
  <img src="docs/screenshots/farm-map.png" width="240" alt="Farm Explorer map" />
  <img src="docs/screenshots/farm-map-zoom.png" width="240" alt="Camera dive into a plot" />
  <img src="docs/screenshots/home.png" width="240" alt="Home dashboard" />
</p>
<p align="center">
  <img src="docs/screenshots/zone-detail.png" width="240" alt="Crop zone detail" />
  <img src="docs/screenshots/livestock.png" width="240" alt="Livestock feeding timeline" />
  <img src="docs/screenshots/chat.png" width="240" alt="Farmly AI assistant" />
</p>

## Highlights

- **Interactive farm map** — board-style extruded 3D plots with per-crop
  interiors (trellised tomatoes, corn rows, lettuce beds, ponds, pastures,
  barns), ambient animation, and a smooth camera dive into any plot.
- **Offline-first writes** — every operation is captured in an immutable
  encrypted outbox on-device and synced when connectivity returns, with
  dependency-aware ordering and conflict recovery.
- **True multi-tenancy** — organizations → farms → zones, enforced by
  PostgreSQL row-level security plus server-side guards.
- **Farmly AI** — contextual assistant (DeepSeek `deepseek-flash`) that
  reasons over the caller's own farm data; credentials stay server-side and
  the app asks for explicit consent before sending farm context.
- **Honest data** — every number carries provenance (sensor/manual/derived)
  and freshness; nothing is silently invented.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│ apps/mobile — Flutter (Android/iOS), Riverpod, go_router   │
│  · isometric Farm Explorer, 5-tab shell, vi-VN UI          │
│  · drift/sqlite encrypted local store + outbox intents     │
│  · sync engine: ordering, lost-ACK reconciliation, retry   │
└──────────────────────────────┬─────────────────────────────┘
                               │ versioned REST contracts
┌──────────────────────────────┴─────────────────────────────┐
│ apps/api — NestJS + Prisma + PostgreSQL                    │
│  · Better Auth sessions, org/farm scope, invitations       │
│  · RLS tenant isolation, mutation kernel, audit            │
│  · farm domain, weather, notifications, privacy, AI        │
└────────────────────────────────────────────────────────────┘

contracts/   versioned request/response schemas + generator
infra/       docker-compose dev stack (PostgreSQL, Mailpit)
tools/qa/    dependency-pin, secrets and preflight checkers
plans/       phase plans, evidence packets, execution ledgers
```

## Getting started

### API

```powershell
cp infra/.env.example infra/.env        # fill unique local-only secrets
docker compose -f infra/compose.yaml --env-file infra/.env config --quiet
npm --prefix apps/api ci
npm --prefix apps/api run start:dev
```

The API rejects `MIGRATION_DATABASE_URL` at runtime — migration credentials
live only in the migration process. See `apps/api` scripts for the ordered
migration chain (`migrate:auth` → `migrate:tenant` → `migrate:rls` → …).

### Mobile

```powershell
cd apps/mobile
flutter pub get

# Visual preview without a backend — stub session + demo farm data:
flutter run --flavor development -t lib/main_explorer_preview.dart

# Full app (needs a running API):
flutter run --flavor development -t lib/main.dart
```

## Verification

```powershell
npm --prefix apps/api run build
npm --prefix apps/api run test:unit
node contracts/scripts/build-contracts.mjs --check
node tools/qa/preflight.mjs --json

cd apps/mobile
flutter analyze
flutter test            # unit + widget + golden suite
```

## Project status

Foundation build in active development. Golden-tested UI for the six primary
screens, demo-data preview entrypoint, and the sync/RLS kernel are in place;
live-device journeys, live DeepSeek calls and release packaging remain gated
on credentials and hardware. See
[`plans/261005-1435-farmly-mobile-app/plan.md`](plans/261005-1435-farmly-mobile-app/plan.md)
for scope, evidence and current gates.
