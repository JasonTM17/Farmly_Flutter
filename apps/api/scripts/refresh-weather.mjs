// P07 weather snapshot refresh job (spec03 P-05, spec04 weather read cache).
//
// Runs as a control-plane job (`docker compose run api-runner node scripts/
// refresh-weather.mjs`, cron, or worker). Connects as farmly_tenant_app; the
// only surface it can touch is the pair of SECURITY DEFINER weather functions —
// farmly_weather_refresh_targets() enumerates stale farms and
// farmly_record_weather_snapshot() validates+binds the row to the farm's
// configured coarse grid.
//
// Privacy (P-05): the provider request carries ONLY the coarse grid ref
// (lat,lon rounded to 0.1° by kernel CHECK) plus fixed forecast parameters.
// No farm/org/user IDs, names, or exact coordinates ever leave this host.
// Kill switch: WEATHER_ENABLED=false → no egress at all.

import { Client } from 'pg';

const PROVIDER = 'open-meteo';

function required(name) {
  const value = process.env[name];
  if (!value) {
    process.stderr.write(`refresh-weather: ${name} required\n`);
    process.exit(2);
  }
  return value;
}

async function main() {
  if (process.env.WEATHER_ENABLED !== 'true') {
    process.stdout.write(JSON.stringify({ status: 'skipped', reason: 'weather_disabled' }) + '\n');
    return;
  }
  const baseUrl = (process.env.WEATHER_BASE_URL ?? 'https://api.open-meteo.com').replace(/\/$/, '');
  const ttlSeconds = Number(process.env.WEATHER_FRESH_TTL_SECONDS ?? 3600);
  const timeoutMs = Number(process.env.WEATHER_TIMEOUT_MS ?? 4000);

  const client = new Client({ connectionString: required('DATABASE_URL_TENANT') });
  await client.connect();
  try {
    const targets = await client.query(
      'SELECT organization_id, farm_id, grid_ref FROM public.farmly_weather_refresh_targets($1)',
      [ttlSeconds],
    );
    const results = [];
    for (const target of targets.rows) {
      const [lat, lon] = target.grid_ref.split(',');
      // Outgoing bytes: coarse grid + static parameter list only.
      const url = `${baseUrl}/v1/forecast?latitude=${encodeURIComponent(lat)}&longitude=${encodeURIComponent(lon)}`
        + '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&forecast_days=1';
      try {
        const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
        if (!response.ok) throw new Error(`provider_http_${response.status}`);
        const body = await response.json();
        const current = body?.current;
        if (typeof current?.temperature_2m !== 'number' || typeof current?.weather_code !== 'number') {
          throw new Error('provider_payload_invalid');
        }
        const payload = {
          temperatureC: current.temperature_2m,
          humidityPercent: current.relative_humidity_2m ?? null,
          windKph: current.wind_speed_10m ?? null,
          weatherCode: current.weather_code,
          units: body?.current_units ?? {},
        };
        // valid_at = the provider's "current" observation instant.
        const validAt = typeof current.time === 'string' && !Number.isNaN(Date.parse(current.time))
          ? current.time
          : new Date().toISOString();
        await client.query(
          `SELECT public.farmly_record_weather_snapshot($1, $2, $3, $4, $5::timestamptz, $6::jsonb)`,
          [target.organization_id, target.farm_id, PROVIDER, target.grid_ref, validAt, JSON.stringify(payload)],
        );
        results.push({ farmId: target.farm_id, status: 'refreshed' });
      } catch (error) {
        // Stale cache stays in place; the read surface reports it as stale.
        results.push({
          farmId: target.farm_id,
          status: 'failed',
          reason: error instanceof Error ? error.message : 'unknown',
        });
      }
    }
    process.stdout.write(JSON.stringify({ status: 'done', refreshed: results }) + '\n');
  } finally {
    await client.end();
  }
}

await main();
