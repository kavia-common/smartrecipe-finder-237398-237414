# SnapChef DB migrations (demo-auth mode)

This database container uses a lightweight approach:

- `../init_snapchef_schema.sql` contains **idempotent** DDL + seed data.
- `../startup.sh` applies it when the database is started by the container.
- If PostgreSQL is already running and `startup.sh` exits early, you can still apply the schema/seed by running:

```bash
./apply_migrations.sh
```

Notes:
- The SQL is written to be safe to run multiple times (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`).
- Seed data is intended for development/demo environments.
