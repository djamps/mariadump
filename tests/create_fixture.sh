#!/bin/bash

# create_fixture.sh - Generate MariaDB data directory fixture for testing
# Usage: ./create_fixture.sh [version]
# Default version: 10.6
# Supports Docker tags >= 5.5

set -euo pipefail

VERSION=${1:-10.6}

# Validate version >= 5.5
if ! awk -v ver="$VERSION" 'BEGIN { split(ver, a, "."); if (a[1] < 5 || (a[1] == 5 && a[2] < 5)) exit 1 }'; then
    echo "Error: Unsupported MariaDB version $VERSION. Minimum supported is 5.5." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
SQL_FILE="$FIXTURES_DIR/testdb.sql"
OUTPUT_FILE="$FIXTURES_DIR/mariadb-$VERSION.tar.gz"

if [[ ! -f "$SQL_FILE" ]]; then
    echo "Error: $SQL_FILE not found." >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d)
DATA_DIR="$TEMP_DIR/data"
CONTAINER_NAME="mariadb_fixture_$VERSION"

echo "Creating fixture for MariaDB $VERSION..."

# Start MariaDB container with empty data dir
docker run --name "$CONTAINER_NAME" \
    -e MYSQL_ROOT_PASSWORD=rootpass \
    -e MYSQL_DATABASE=testdb \
    -v "$DATA_DIR:/var/lib/mysql" \
    -d "mariadb:$VERSION"

# Wait for startup
sleep 30

# Check connection
until docker exec "$CONTAINER_NAME" mysql -u root -prootpass -e "SELECT 1;" > /dev/null 2>&1; do
    echo "Waiting for MariaDB to be ready..."
    sleep 5
done

# Import the SQL file
docker exec -i "$CONTAINER_NAME" mysql -u root -prootpass testdb < "$SQL_FILE"

# Stop container
docker stop "$CONTAINER_NAME"

# Create mysql_upgrade_info as fallback for auto-detection (used only if ib_logfile0 detection fails)
mkdir -p "$DATA_DIR/mysql"
echo "$VERSION" > "$DATA_DIR/mysql/mysql_upgrade_info"

# Compress the data directory
tar -czf "$OUTPUT_FILE" -C "$DATA_DIR" .

# Cleanup
docker rm "$CONTAINER_NAME"
rm -rf "$TEMP_DIR"

echo "Fixture created: $OUTPUT_FILE"