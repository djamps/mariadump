#!/bin/sh

# Color definitions (ANSI escape codes)
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Start MariaDB in recovery mode (bypasses password/auth), with optional InnoDB force recovery and mariadb args
printf "%b\n" "${GREEN}Starting MariaDB in recovery mode...${RESET}"
RECOVERY="${INNODB_FORCE_RECOVERY:-0}"
MARIADB_ARGS="${MARIADB_ARGS:-}"
if [ -n "$MARIADB_ARGS" ]; then
    /usr/local/bin/docker-entrypoint.sh mysqld --skip-grant-tables --innodb-force-recovery="$RECOVERY" "$MARIADB_ARGS" &
else
    /usr/local/bin/docker-entrypoint.sh mysqld --skip-grant-tables --innodb-force-recovery="$RECOVERY" &
fi
pid=$!

# Wait for MariaDB to be ready (loop until ready or crash)
while true; do
  # Check if process crashed (exited prematurely)
  if ! kill -0 $pid 2>/dev/null; then
    printf "%b\n" "${RED}No dumps created.${RESET}"
    exit 10
  fi

  if mysqladmin ping -u root --silent; then
    break
  fi
  sleep 1
done

printf "%b\n" "${GREEN}MariaDB started successfully, proceeding.${RESET}"

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

# If list mode, list databases or tables instead of dumping
if [ -n "${LIST_MODE}" ]; then
  if [ -n "${SPECIFIC_DB}" ]; then
    # Check if database exists
    db_exists=$(mysql -u root -e "SHOW DATABASES LIKE '${SPECIFIC_DB}';")
    if [ -z "$db_exists" ]; then
      printf "%b\n" "${RED}Database ${SPECIFIC_DB} does not exist.${RESET}"
      kill $pid
      wait $pid
      exit 30
    fi

    printf "%b\n" "${GREEN}Tables in database ${SPECIFIC_DB}:${RESET}"
    tables=$(mysql -u root -e "USE \`${SPECIFIC_DB}\`; SHOW TABLES;" | tail -n +2)
    for table in $tables; do
      printf "%b\n" "${YELLOW}${table}${RESET}"
    done
  else
    printf "%b\n" "${GREEN}Non-system databases:${RESET}"
    databases=$(mysql -u root -e "SHOW DATABASES;" | tail -n +2 | grep -v -E 'mysql|information_schema|performance_schema')
    for db in $databases; do
      printf "%b\n" "${YELLOW}${db}${RESET}"
    done
  fi

  # Cleanly stop MariaDB and exit
  kill $pid
  wait $pid
  exit 0
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
      exit 20
    fi
     printf "%b\n" "${YELLOW}Dumping specific table: ${db}.${table}${RESET}"
     DUMP_CMD="mysqldump -u root \"${db}\" \"${table}\" ${MYSQLDUMP_ARGS}"
     eval "$DUMP_CMD ${COMPRESS_PIPE}" > "/dumps/${db}.${table}${EXT}"
     printf "%b\n" "${GREEN}Dump of table ${db}.${table} completed.${RESET}"
  else
    printf "%b\n" "${RED}Invalid specific table format. Skipping dump.${RESET}"
    kill $pid
    wait $pid
    exit 21
  fi

# If specific database is requested
elif [ -n "${SPECIFIC_DB}" ]; then
  # Check if database exists
  db_exists=$(mysql -u root -e "SHOW DATABASES LIKE '${SPECIFIC_DB}';")
  if [ -z "$db_exists" ]; then
    printf "%b\n" "${RED}Database ${SPECIFIC_DB} does not exist. Skipping dump.${RESET}"
    kill $pid
    wait $pid
    exit 30
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
   printf "%b\n" "${GREEN}Dump of database ${SPECIFIC_DB} completed.${RESET}"

# Else, dump all non-system databases
else
  # Get list of databases, excluding system ones
  databases=$(mysql -u root -e "SHOW DATABASES;" | tail -n +2 | grep -v -E 'mysql|information_schema|performance_schema')

   # Dump each database to a gzipped file in /dumps
   for db in $databases; do
     printf "%b\n" "${YELLOW}Dumping database: $db${RESET}"
     DUMP_CMD="mysqldump -u root --databases \"$db\" ${MYSQLDUMP_ARGS}"
     eval "$DUMP_CMD ${COMPRESS_PIPE}" > "/dumps/${db}${EXT}"
     printf "%b\n" "${GREEN}Dump of database $db completed.${RESET}"
   done
fi

printf "%b\n" "${GREEN}Dumping complete.${RESET}"

# Cleanly stop MariaDB and exit
kill $pid
wait $pid
exit 0
