#!/bin/bash

# Universal Database Backup Script
# Automatically detects and backs up the running database

DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

# SQLite check and backup
if [ -f "${DB_NAME}" ]; then
    echo "Backing up SQLite database..."
    cp "${DB_NAME}" "database_backup.db"
    echo "✓ Backup saved to database_backup.db"
    exit 0
fi

# PostgreSQL check and backup
PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | head -1)
if [ -n "$PG_VERSION" ]; then
    PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
    if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
        echo "Backing up PostgreSQL database..."
        PGPASSWORD="${DB_PASSWORD}" ${PG_BIN}/pg_dump \
            -h localhost -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} \
            --clean --if-exists --create > database_backup.sql
        echo "✓ Backup saved to database_backup.sql"
        exit 0
    fi
fi

# MySQL check and backup - Fixed to use correct port and TCP connection
# Check if MySQL is running on the specified port
if mysqladmin ping -h localhost -P ${DB_PORT} --silent 2>/dev/null || \
   sudo mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent 2>/dev/null; then
    echo "Backing up MySQL database..."
    
    # First try with TCP connection on specified port (for Docker or custom port setups)
    if mysql -h localhost -P ${DB_PORT} -u ${DB_USER} -p${DB_PASSWORD} \
        -e "SELECT 1" >/dev/null 2>&1; then
        mysqldump -h localhost -P ${DB_PORT} \
            -u ${DB_USER} -p${DB_PASSWORD} \
            --databases ${DB_NAME} --add-drop-database \
            --routines --triggers --single-transaction > database_backup.sql
        echo "✓ Backup saved to database_backup.sql (via TCP port ${DB_PORT})"
        exit 0
    fi
    
    # Fallback to root user with TCP if appuser doesn't work
    if mysql -h localhost -P ${DB_PORT} -u root -p${DB_PASSWORD} \
        -e "SELECT 1" >/dev/null 2>&1; then
        mysqldump -h localhost -P ${DB_PORT} \
            -u root -p${DB_PASSWORD} \
            --databases ${DB_NAME} --add-drop-database \
            --routines --triggers --single-transaction > database_backup.sql
        echo "✓ Backup saved to database_backup.sql (via TCP port ${DB_PORT} as root)"
        exit 0
    fi
    
    # Final fallback to socket connection for standard MySQL installations
    if sudo mysql --socket=/var/run/mysqld/mysqld.sock \
        -u root -p${DB_PASSWORD} -e "SELECT 1" >/dev/null 2>&1; then
        sudo mysqldump --socket=/var/run/mysqld/mysqld.sock \
            -u root -p${DB_PASSWORD} \
            --databases ${DB_NAME} --add-drop-database \
            --routines --triggers --single-transaction > database_backup.sql
        echo "✓ Backup saved to database_backup.sql (via socket)"
        exit 0
    fi
    
    # Try without password for local root
    if sudo mysql --socket=/var/run/mysqld/mysqld.sock \
        -u root -e "SELECT 1" >/dev/null 2>&1; then
        sudo mysqldump --socket=/var/run/mysqld/mysqld.sock \
            -u root \
            --databases ${DB_NAME} --add-drop-database \
            --routines --triggers --single-transaction > database_backup.sql
        echo "✓ Backup saved to database_backup.sql (via socket, no password)"
        exit 0
    fi
    
    echo "⚠ MySQL is running but authentication failed"
    echo "  Please check your credentials"
    exit 1
fi

# MongoDB check and backup
if mongosh --port ${DB_PORT} --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
    echo "Backing up MongoDB database..."
    mongodump --port ${DB_PORT} --db ${DB_NAME} \
        --archive=database_backup.archive --quiet
    echo "✓ Backup saved to database_backup.archive"
    exit 0
fi

echo "⚠ No running database detected"
echo "Make sure your database is running before creating a backup"
exit 1
