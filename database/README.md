# SnapChef Database (PostgreSQL)

This container provides the PostgreSQL database used by SnapChef (demo-auth mode).

## Connection

After running `startup.sh`, a connection helper is written to:

- `db_connection.txt` (contains a `psql postgresql://...` command)

Example:

```bash
cat db_connection.txt
# psql postgresql://appuser:...@localhost:5000/myapp
```

## Schema + seed data

SnapChef’s schema and demo seed data live in:

- `init_snapchef_schema.sql`

It is **idempotent** and safe to run multiple times.

### Automatic init

`startup.sh` applies `init_snapchef_schema.sql` after creating the database/user when it starts PostgreSQL itself.

### Manual apply (recommended when Postgres is already running)

If PostgreSQL is already up (and `startup.sh` exits early), apply schema/seed with:

```bash
./apply_migrations.sh
```

## What’s included in the schema

- `users` (demo auth users)
- `scans`
- `recipes`
- `recipe_ingredients`
- `favorites`
- `shopping_lists`, `shopping_list_items`
- `meal_plans`, `meal_plan_entries`
- `analytics_events`
