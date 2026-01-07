#!/bin/sh

# Color definitions (ANSI escape codes)
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Start MariaDB in recovery mode (bypasses password/auth), with optional InnoDB force recovery and mariadb args
RECOVERY="${INNODB_FORCE_RECOVERY:-0}"
MARIADB_ARGS="${MARIADB_ARGS:-}"
/usr/local/bin/docker-entrypoint.sh mysqld --skip-grant-tables --innodb-force-recovery="$RECOVERY" ${MARIADB_ARGS} &
pid=$!

# Wait for MariaDB to be ready (loop until ready or crash)
ready=0
while true; do
  # Check if process crashed (exited prematurely)
  if ! kill -0 $pid 2>/dev/null; then
    printf "%b\n" "${RED}MariaDB process crashed or exited early. Exiting without dumping.${RESET}"
    exit 1
  fi

  if mysqladmin ping -u root --silent; then
    ready=1
    break
  fi
  sleep 1
done

printf "%b\n" "${GREEN}MariaDB started successfully. Proceeding with dumps.${RESET}"

# mysqldump args (if provided)
MYSQLDUMP_ARGS="${MYSQLDUMP_ARGS:-}"

# Compression handling (default to gz; skip if NOCOMPRESS set)
if [ -n "${NOCOMPRESS}" ]; then
  EXT=".sql"
  COMPRESS_PIPE=""
else
  EXT=".sql.gz"
  COMPRESS_PIPE="| gzip"
fi

# If specific table is requested (format: db.table)
if [ -n "${SPECIFIC_TABLE}" ]; then
  db=$(echo "${SPECIFIC_TABLE}" | cut -d. -f1)
  table=$(echo "${SPECIFIC_TABLE}" | cut -d. -f2)
  if [ -n "$db" ] && [ -n "$table" ]; then
    # Check if table exists
    table_exists=$(mysql -u root -e "USE \`${db}\`; SHOW TABLES LIKE '${table}';")
    if [ -z "$table_exists" ]; then
      printf "%b\n" "${RED}Table ${db}.${table} does not exist. Skipping dump.${RESET}"
      kill $pid
      wait $pid
      exit 1
    fi
    printf "%b\n" "${YELLOW}Dumping specific table: ${db}.${table}${RESET}"
    DUMP_CMD="mysqldump -u root \"${db}\" \"${table}\" ${MYSQLDUMP_ARGS}"
    eval "$DUMP_CMD ${COMPRESS_PIPE}" > "/dumps/${db}.${table}${EXT}"
  else
    printf "%b\n" "${RED}Invalid specific table format. Skipping dump.${RESET}"
    kill $pid
    wait $pid
    exit 1
  fi

# If specific database is requested
elif [ -n "${SPECIFIC_DB}" ]; then
  # Check if database exists
  db_exists=$(mysql -u root -e "SHOW DATABASES LIKE '${SPECIFIC_DB}';")
  if [ -z "$db_exists" ]; then
    printf "%b\n" "${RED}Database ${SPECIFIC_DB} does not exist. Skipping dump.${RESET}"
    kill $pid
    wait $pid
    exit 1
  fi

  printf "%b\n" "${YELLOW}Dumping database: ${SPECIFIC_DB}${RESET}"

  # Build ignore-table flags if skips provided (comma-separated)
  ignore_flags=""
  if [ -n "${SKIP_TABLES}" ]; then
    oldIFS="$IFS"
    IFS=','
    for skip in ${SKIP_TABLES}; do
      ignore_flags="${ignore_flags} --ignore-table=${SPECIFIC_DB}.${skip}"
    done
    IFS="$oldIFS"
  fi

  # Dump the database (with ignores if any, and mysqldump args)
  DUMP_CMD="mysqldump -u root --databases \"${SPECIFIC_DB}\" ${ignore_flags} ${MYSQLDUMP_ARGS}"
  eval "$DUMP_CMD ${COMPRESS_PIPE}" > "/dumps/${SPECIFIC_DB}${EXT}"

# Else, dump all non-system databases
else
  # Get list of databases, excluding system ones
  databases=$(mysql -u root -e "SHOW DATABASES;" | tail -n +2 | grep -v -E 'mysql|information_schema|performance_schema')

  # Dump each database to a gzipped file in /dumps
  for db in $databases; do
    printf "%b\n" "${YELLOW}Dumping database: $db${RESET}"
    DUMP_CMD="mysqldump -u root --databases \"$db\" ${MYSQLDUMP_ARGS}"
    eval "$DUMP_CMD ${COMPRESS_PIPE}" > "/dumps/${db}${EXT}"
  done
fi

printf "%b\n" "${GREEN}Dumping complete.${RESET}"

# Cleanly stop MariaDB and exit
kill $pid
wait $pid
exit 0
