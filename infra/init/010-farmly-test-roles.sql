\getenv auth_password FARMLY_TEST_AUTH_PASSWORD
\getenv tenant_password FARMLY_TEST_TENANT_PASSWORD
\getenv migration_password FARMLY_TEST_MIGRATION_PASSWORD

CREATE ROLE farmly_auth_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD :'auth_password';
CREATE ROLE farmly_tenant_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD :'tenant_password';
CREATE ROLE farmly_migration LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD :'migration_password';

GRANT CONNECT ON DATABASE farmly_test_261005 TO farmly_auth_app, farmly_tenant_app, farmly_migration;
REVOKE TEMPORARY ON DATABASE farmly_test_261005 FROM PUBLIC;
GRANT CREATE ON DATABASE farmly_test_261005 TO farmly_migration;
GRANT CREATE ON SCHEMA public TO farmly_migration;

-- Test-observability grant: lets the migration-role test harness inspect
-- pg_stat_activity wait events for other-role sessions. Test database only.
GRANT pg_monitor TO farmly_migration;

\unset auth_password
\unset tenant_password
\unset migration_password
