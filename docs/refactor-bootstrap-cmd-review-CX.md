# PostgreSQL Helper Command Review (CX)

This note captures follow-up items identified while reviewing the commands surfaced via `psqlhelp()` inside `bash/app/postgresql.bash`.

## `psql_bootstrap`
- Guard SQL input properly: user, database, and password values are interpolated inside single quotes (e.g., `CREATE USER "$user_name" WITH PASSWORD '$password'`). Passwords containing quotes break the statement and open the door for SQL injection. Use `psql` variables (`\set db :'var'`) or dollar-quoting (`$$`) so arbitrary strings are safe.
- Least privilege: the implementation always grants both `CREATEDB` **and** `CREATEROLE` (`ALTER ROLE ... WITH CREATEDB CREATEROLE`). The spec only requires `CREATEDB`; granting `CREATEROLE` is unnecessary and risky. Expose explicit flags (e.g., `--createrole`) or prompt before elevating capabilities.
- Service rewrite: when the alias already exists, the command aborts the save step. That prevents password rotation or alias metadata refresh even after a successful role change. Offer a `--force` flag (default `n`) that rewrites the `PG_SERVICES_FILE` entry so `.pg_service.conf` stays in sync.
- Default privileges: the GRANT block only covers existing objects (`GRANT ALL PRIVILEGES ON DATABASE/SCHEMA`). New tables/sequences created later by other owners will remain inaccessible. Add `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ... TO "$user"` to keep permissions consistent.
- Secrets at rest: the helper appends credentials into `~/.config/pg_services.list` without ensuring the file is `0600`. Call `chmod 0600 "$PG_SERVICES_FILE"` whenever the file is created or rewritten to avoid leaking passwords on multi-user systems.

## `psql_sync`
- Alias conflicts: the loop writes `"$db" "$db" "$owner" ...` without re-checking whether a service named `$db` already exists. When a user already has a custom alias pointing at the same database, the sync produces duplicates. Compare against both the alias and `dbname` fields before writing.
- Stale service cache: the function appends new items with `printf ... >> "$PG_SERVICES_FILE"` but keeps using the pre-call `services[]` array for the remainder of the loop. Reload the array immediately after each addition (or work against a temporary copy) so subsequent checks see freshly added aliases.
- Password capture UX: the flow prompts once for the owner password and silently skips when empty. Users often paste the wrong secret and only learn after attempting to `psql_<alias>`. Offer a confirmation prompt or a `ux_warning` detailing how to re-run `psql_sync` to patch the entry.

## `psql_add`
- Host/port parity: saved entries only capture alias, db, user, password—the helpers hard-code `localhost:5432`. Allow optional host/port inputs (defaulted to the current environment) so remote clusters and alternate ports can be described.
- File permissions: similar to bootstrap, writing into `PG_SERVICES_FILE` never re-applies `chmod 0600`. Apply the same hardening path after appends to ensure secrets stay private.
- UX consistency: the non-interactive usage when arguments are missing simply prints `ux_error "Alias is required"` but never shows `ux_usage`. Surfacing `ux_usage "psql_add" "" "Link an existing database"` would align with the UX guidelines.

## `psql_del`
- SQL injection & quoting: values from `services[]` are interpolated without double quotes inside `pg_terminate_backend`, `DROP DATABASE`, and `DROP ROLE`. Alias or db names containing double quotes/uppercase will fail, and malicious values could break out of the statement. Wrap identifiers via `quote_ident()` or `"${var//\"/\"\"}"`.
- Permission clean-up: when only the service entry is removed (user answers "n" to dropping database/user), `.pg_service.conf` is regenerated but lingering `PGPASSFILE`/`PGSERVICE` references remain. Consider offering a `--dry-run` preview and explicitly telling the user where credentials still live.

## `psql_<alias>` connection functions
- Missing validation: `psql_<svc>` wrappers blindly export `PGSERVICE` and run `psql`. When the referenced alias has been deleted or the `.pg_service.conf` is stale, the call fails with a terse libpq error. Add a guard that checks `grep -q "^\[$svc\]" "$PGSERVICE_CONF"` and prints a UX-friendly error to encourage running `psql_sync`.

## `psql_db`
- Drop safety: `psql_db delete` issues `DROP DATABASE` without first terminating connections, so the call routinely fails while active sessions exist. Reuse the termination logic implemented in `psql_del`.
- Grant defaults: similar to bootstrap, the `grant` subcommand does not run `ALTER DEFAULT PRIVILEGES`, so future tables revert to the default ACL. Extend the grant logic to keep permissions sticky.
- Usage UX: the command prints plain `echo "Usage: ..."` strings instead of `ux_usage`. Align with `UX_GUIDELINES.md` by invoking `ux_usage`/`ux_error` under the `*)` branch.

## `psql_user`
- Quoting: statements such as `CREATE USER $arg1 WITH PASSWORD '$arg2'` and `DROP USER $arg1` do not quote identifiers, making it impossible to manage camelCase names and opening the door to injection. Switch to `quote_ident()` or double-quote escaping.
- Attribute toggles: `psql_user attr` repeatedly prompts for each property and immediately runs an ALTER statement after every answer. Batch the desired attributes and execute a single `ALTER ROLE` so permission changes are atomic and easier to audit.
- Help surface: like `psql_db`, the fallback usage text is sent via `echo`. Replace it with `ux_usage` to maintain the standard help + coloring rules.
