# Farmly API container preview

Farmly publishes a public, pre-release API container to GitHub Container
Registry (GHCR). This preview is built for `linux/amd64`; it is not a mobile
app package, production deployment, or claim that Farmly R1 is release-ready.
The image contains the compiled API and production runtime dependencies. It
runs as the unprivileged `node` user and does not include the repository's
`.env`, tests, migrations, Prisma CLI, or npm package manager.

> **Security notice for the first preview:** the local candidate image was
> scanned with Trivy 0.75.0 on 2026-10-20. It reported 43 HIGH Debian 13.7
> findings, zero CRITICAL findings, and no fixed versions for the HIGH results.
> The full unfiltered scan also found one UNKNOWN, CVE-2026-82560, attributed
> to `perl-base@5.40.1-6+deb13u1`. The [Debian tracker](https://security-tracker.debian.org/tracker/CVE-2026-82560)
> describes this CVE in `Pod::Text`, and Debian lists `Pod/Text.pm` in the
> [`perl-modules-5.40` file list](https://packages.debian.org/trixie/all/perl-modules-5.40/filelist), which is absent from this
> image. An independent review of the exact image digest confirmed that the
> module file is absent and Perl cannot import it, so this report entry is
> cleared as not applicable to this image. The unfiltered report still retains
> the UNKNOWN entry. Before applying this exact-tag clearance, the workflow
> rechecks the scanned image for the module and verifies that the finding still
> matches the reviewed Debian package, version, and target.
> The user authorized this one preview with a cap of 43 HIGH and zero CRITICAL.
> Every other UNKNOWN finding blocks publication; other release tags remain
> strict for HIGH, CRITICAL, and UNKNOWN findings.
> The publish workflow re-scans the exact release
> image without filtering severities and attaches the full JSON report to its
> run. Do not use this preview as a production deployment. Any other release
> tag remains blocked by HIGH, CRITICAL, or UNKNOWN findings.

## Pull and pin an image

The first preview uses a version tag and a full source-commit tag:

```sh
docker pull ghcr.io/jasontm17/farmly-api:0.1.0-preview.1
docker pull ghcr.io/jasontm17/farmly-api:sha-<full-commit-sha>
```

For a deployment that must remain fixed to one artifact, use the verified
registry digest recorded by the release workflow:

```sh
docker pull ghcr.io/jasontm17/farmly-api@sha256:<image-digest>
```

The version and full-SHA tags are expected to resolve to the same digest. There
is no `latest` tag. The package is linked to this repository through its OCI
source label; public visibility is verified separately from repository
linkage.

## Runtime configuration

Supply runtime configuration through the deployment platform's secret manager
or a local env file kept outside the image build context. Never put credentials
in Docker build arguments, image labels, source control, or this documentation.

Required variables:

| Variable | Requirement |
| --- | --- |
| `DATABASE_URL_TENANT` | PostgreSQL connection URL for tenant data. |
| `DATABASE_URL_AUTH` | PostgreSQL connection URL for authentication data. |
| `BETTER_AUTH_SECRET` | At least 32 characters. |
| `BETTER_AUTH_URL` | Public base URL; use HTTPS when `NODE_ENV=production`. |
| `CURSOR_SIGNING_KEY` | At least 32 characters. |

`NODE_ENV` defaults to `production` in the image. `PORT` defaults to `3000`.
Production configuration must set either `SMTP_SECURE=true` or
`SMTP_REQUIRE_TLS=true`; the API enforces this even when SMTP credentials are
omitted. Use the option supported by the mail server: `SMTP_SECURE` for implicit
TLS or `SMTP_REQUIRE_TLS` for mandatory STARTTLS.

Example using a local env file supplied at runtime (the file is not included in
the repository):

```sh
docker run --rm \
  --name farmly-api \
  --env-file ./farmly-api.runtime.env \
  --publish 3000:3000 \
  ghcr.io/jasontm17/farmly-api:0.1.0-preview.1
```

The image does not run database migrations. Apply the versioned API migrations
through the repository's operator workflow before relying on the service.

## Health and readiness

The Docker healthcheck calls `/health/live`. A successful response confirms
that the process is serving HTTP; it does not prove database connectivity or
schema readiness. `/health/ready` checks dependencies and should be used by an
operator only after the required databases and migrations are available.

## Verify release attestations

Install the GitHub CLI with artifact-attestation support, then verify the
registry image's build provenance and SPDX SBOM against the repository:

```sh
gh attestation verify oci://ghcr.io/jasontm17/farmly-api:0.1.0-preview.1 \
  -R JasonTM17/Farmly_Flutter

gh attestation verify oci://ghcr.io/jasontm17/farmly-api:0.1.0-preview.1 \
  -R JasonTM17/Farmly_Flutter \
  --predicate-type https://spdx.dev/Document/v2.3
```

The tag workflow validates the API preview version, builds once, scans the
image, stores the full unfiltered Trivy JSON artifact, generates the SBOM, and
runs `/health/live` before it pushes either tag. The exact first-preview tag
has a one-time cap of 43 HIGH and zero CRITICAL findings, plus the single
image-specific non-applicability clearance for `CVE-2026-82560` described
above. Any other UNKNOWN finding blocks publication; all other tags are
blocked by any HIGH/CRITICAL/UNKNOWN result. The workflow publishes only when
both destination tags are confirmed absent. If an interrupted run has written
either tag, the retry inspects both references and stops without pushing,
deleting, or replacing either tag. Inspect the tag digests and attestations
read-only, retain the run report, and get release-owner direction before any
new release identity is used. Farmly R1 packaging and production-readiness
gates remain separate.
