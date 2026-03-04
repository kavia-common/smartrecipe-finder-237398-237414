#!/bin/bash
set -euo pipefail

# Applies SnapChef schema + seed data to the running PostgreSQL instance.
# Uses the connection string saved by startup.sh in db_connection.txt.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONN_FILE="${SCRIPT_DIR}/db_connection.txt"
SCHEMA_FILE="${SCRIPT_DIR}/init_snapchef_schema.sql"

if [ ! -f "${CONN_FILE}" ]; then
  echo "ERROR: ${CONN_FILE} not found."
  echo "Run startup.sh first (or create db_connection.txt) so we know how to connect."
  exit 1
fi

if [ ! -f "${SCHEMA_FILE}" ]; then
  echo "ERROR: ${SCHEMA_FILE} not found."
  exit 1
fi

CONN_CMD="$(cat "${CONN_FILE}")"

echo "Applying SnapChef schema/seed using: ${CONN_CMD}"
# Execute migration/seed file
${CONN_CMD} -v ON_ERROR_STOP=1 -f "${SCHEMA_FILE}"

echo "Done."
