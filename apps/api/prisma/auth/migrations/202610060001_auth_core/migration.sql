CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE auth."user" (
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    "emailVerified" BOOLEAN NOT NULL DEFAULT FALSE,
    image TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT user_pkey PRIMARY KEY (id),
    CONSTRAINT user_email_key UNIQUE (email)
);

CREATE TABLE auth.session (
    id TEXT NOT NULL,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    token TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    "ipAddress" TEXT,
    "userAgent" TEXT,
    "userId" TEXT NOT NULL,
    CONSTRAINT session_pkey PRIMARY KEY (id),
    CONSTRAINT session_token_key UNIQUE (token),
    CONSTRAINT session_userId_fkey FOREIGN KEY ("userId") REFERENCES auth."user"(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX session_userId_idx ON auth.session("userId");

CREATE TABLE auth.account (
    id TEXT NOT NULL,
    "accountId" TEXT NOT NULL,
    "providerId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "accessToken" TEXT,
    "refreshToken" TEXT,
    "idToken" TEXT,
    "accessTokenExpiresAt" TIMESTAMPTZ(6),
    "refreshTokenExpiresAt" TIMESTAMPTZ(6),
    scope TEXT,
    password TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT account_pkey PRIMARY KEY (id),
    CONSTRAINT account_userId_fkey FOREIGN KEY ("userId") REFERENCES auth."user"(id) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX account_userId_idx ON auth.account("userId");

CREATE TABLE auth.verification (
    id TEXT NOT NULL,
    identifier TEXT NOT NULL,
    value TEXT NOT NULL,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT verification_pkey PRIMARY KEY (id)
);

CREATE INDEX verification_identifier_idx ON auth.verification(identifier);

CREATE TABLE auth.rate_limit (
    key TEXT NOT NULL,
    count INTEGER NOT NULL,
    "lastRequest" BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT rate_limit_pkey PRIMARY KEY (key)
);

CREATE TABLE auth.verification_token_digest (
    digest CHAR(64) NOT NULL,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT verification_token_digest_pkey PRIMARY KEY (digest)
);

CREATE INDEX verification_token_digest_expiresAt_idx ON auth.verification_token_digest("expiresAt");

GRANT USAGE ON SCHEMA auth TO farmly_auth_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO farmly_auth_app;
ALTER DEFAULT PRIVILEGES FOR ROLE farmly_migration IN SCHEMA auth
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO farmly_auth_app;
