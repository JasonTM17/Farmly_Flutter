ARG NODE_IMAGE=node:24.22.0-trixie-slim@sha256:27526714fd6b7dc938f8cb1665bf1fe749efadadf0145d5bcc07f0fbd0370b60
ARG BUILD_VERSION=0.0.0-dev
ARG VCS_REF=unknown

FROM ${NODE_IMAGE} AS base

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

FROM base AS build

ENV NODE_ENV=development

COPY package.json package-lock.json ./
COPY prisma ./prisma

RUN npm ci --strict-peer-deps --no-audit --no-fund

COPY tsconfig*.json ./
COPY src ./src

RUN npm run build

RUN node --input-type=module -e "import { existsSync } from 'node:fs'; for (const path of ['node_modules/.prisma/client/index.js', 'generated/auth-client/index.js']) if (!existsSync(path)) throw new Error('Missing generated Prisma client: ' + path)"

FROM base AS runtime-deps

COPY package.json package-lock.json ./

# Prisma CLI is an optional peer of production adapters, so omit peer packages as well as dev dependencies.
RUN npm ci --omit=dev --omit=optional --ignore-scripts --strict-peer-deps --no-audit --no-fund \
    && node --input-type=module -e "import { existsSync } from 'node:fs'; if (!existsSync('node_modules/@prisma/client/index.js')) throw new Error('Missing @prisma/client runtime'); for (const path of ['node_modules/prisma', 'node_modules/vitest', 'node_modules/typescript', 'node_modules/tsx']) if (existsSync(path)) throw new Error('Development tooling remains in runtime dependencies: ' + path)"

FROM base AS runtime

ARG BUILD_VERSION
ARG VCS_REF

ENV NODE_ENV=production \
    PORT=3000

LABEL org.opencontainers.image.source="https://github.com/JasonTM17/Farmly_Flutter" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.title="Farmly API"

# npm is needed in build stages only; remove the bundled package manager and its vulnerable package tree.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

COPY --from=runtime-deps --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/generated/auth-client ./generated/auth-client
COPY --chown=node:node package.json ./package.json

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD ["node", "-e", "const p=process.env.PORT||3000;fetch('http://127.0.0.1:'+p+'/health/live').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]

CMD ["node", "dist/main.js"]
