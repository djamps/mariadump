#!/bin/bash

# Color definitions (ANSI escape codes)
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Defaults
DATA_DIR="$(pwd)/mysql"
DUMPS_DIR="$(pwd)/dumps"
USER_VERSION=""
USER_RECOVERY=0
USER_DB=""
USER_SKIP_TABLES=""
USER_TABLE=""
USER_MYSQLDUMP_ARGS=""
USER_MARIADB_ARGS=""
USER_NOCOMPRESS=""
RUN_FLAG=false

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --data-dir)
      DATA_DIR="$2"
      shift 2
      ;;
    --dumps-dir)
      DUMPS_DIR="$2"
      shift 2
      ;;
    --version)
      USER_VERSION="$2"
      shift 2
      ;;
    --recovery)
      USER_RECOVERY="$2"
      shift 2
      ;;
    --database)
      USER_DB="$2"
      shift 2
      ;;
    --skip-tables)
      USER_SKIP_TABLES="$2"
      shift 2
      ;;
    --table)
      USER_TABLE="$2"
      shift 2
      ;;
    --mysqldump-args)
      USER_MYSQLDUMP_ARGS="$2"
      shift 2
      ;;
    --mariadb-args)
      USER_MARIADB_ARGS="$2"
      shift 2
      ;;
    --nocompress)
      USER_NOCOMPRESS="true"
      shift
      ;;
    --run)
      RUN_FLAG=true
      shift
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      exit 1
      ;;
  esac
done

# Validate recovery level (0-6)
if ! [[ "$USER_RECOVERY" =~ ^[0-6]$ ]]; then
  echo -e "${RED}Error: InnoDB force recovery level must be an integer between 0 and 6. Using default 0.${RESET}"
  USER_RECOVERY=0
fi

# Validate table format (db.table)
if [ -n "$USER_TABLE" ] && ! [[ "$USER_TABLE" =~ ^[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+$ ]]; then
  echo -e "${RED}Error: Table must be in format 'db.table'. Ignoring --table.${RESET}"
  USER_TABLE=""
fi

# If --database and --table both set, error (can't combine)
if [ -n "$USER_DB" ] && [ -n "$USER_TABLE" ]; then
  echo -e "${RED}Error: Cannot use --database and --table together. Use one or the other.${RESET}"
  exit 1
fi

# If --skip-tables without --database, ignore or warn
if [ -n "$USER_SKIP_TABLES" ] && [ -z "$USER_DB" ]; then
  echo -e "${YELLOW}Warning: --skip-tables only applies with --database. Ignoring --skip-tables.${RESET}"
  USER_SKIP_TABLES=""
fi

# If --run not specified, show help and exit
if ! $RUN_FLAG; then
  echo "Usage: ./run.sh [options] --run"
  echo ""
  echo "Options:"
  echo "  --data-dir <path>       Specify data directory (default: ./mysql)."
  echo "  --dumps-dir <path>      Specify dumps output directory (default: ./dumps)."
  echo "  --version <tag>         Specify MariaDB Docker tag (e.g., 10.3). If omitted, auto-detects from data."
  echo "  --recovery <0-6>        Set InnoDB force recovery level (default: 0). Higher values for corrupt data."
  echo "  --database <db_name>    Dump only a specific database (overrides full dumps and --table)."
  echo "  --skip-tables <t1,t2>   Comma-separated tables to skip in the database (only with --database; for corrupt tables)."
  echo "  --table <db.table>      Dump only a specific database table (overrides full dumps and --database)."
  echo "  --mysqldump-args \"arg1 arg2\"  Pass raw arguments to mysqldump (e.g., \"--skip-add-drop-table --skip-add-locks\"; applies to all dumps)."
  echo "  --mariadb-args \"arg1 arg2\"    Pass raw arguments to mariadb server (e.g., \"--innodb-buffer-pool-size=1G\"; appended to mysqld)."
  echo "  --nocompress            Output plain .sql files instead of .sql.gz (applies to all dumps)."
  echo ""
  echo "Examples:"
  echo "  ./run.sh --run                              # Auto-detect version, recovery 0, all databases"
  echo "  ./run.sh --recovery 4 --run                 # Auto-detect version, recovery 4, all databases"
  echo "  ./run.sh --version 10.3 --run               # Version 10.3, recovery 0, all databases"
  echo "  ./run.sh --database mydb --run              # Auto-detect version, recovery 0, only mydb"
  echo "  ./run.sh --database mydb --skip-tables bad1,bad2 --run  # Auto-detect, recovery 0, mydb skipping bad1/bad2"
  echo "  ./run.sh --table mydb.mytable --run         # Auto-detect version, recovery 0, only mydb.mytable"
  echo "  ./run.sh --version 10.3 --recovery 2 --database mydb --skip-tables bad1 --mysqldump-args \"--skip-add-drop-table\" --mariadb-args \"--innodb-buffer-pool-size=1G\" --nocompress --run  # All relevant options"
  echo "  ./run.sh --data-dir /path/to/data --dumps-dir /path/to/dumps --run  # Custom directories"
  exit 0
fi

mkdir -p "$DATA_DIR" "$DUMPS_DIR"

# Check for PID file in data dir to detect live database
PID_FILE=""
for file in "$DATA_DIR"/*.pid; do
  if [ -f "$file" ]; then
    PID_FILE="$file"
    break
  fi
done

if [ -n "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    PROC_NAME=$(ps -p "$PID" -o comm= 2>/dev/null)
    if [ "$PROC_NAME" = "mysqld" ] || [ "$PROC_NAME" = "mariadbd" ]; then
      echo -e "${RED}Live database detected (PID $PID running $PROC_NAME). Aborting to prevent damage.${RESET}"
      exit 1
    fi
  fi
fi

# === AUTO-DETECT MARIADB TAG IF NOT PROVIDED ===
if [ -z "$USER_VERSION" ]; then
  DETECTED_TAG=""

  # Prefer ib_logfile0 (has clear MySQL vs MariaDB prefix)
  if [ -f "$DATA_DIR/ib_logfile0" ]; then
    VER_LINE=$(dd bs=1 skip=16 count=50 if="$DATA_DIR/ib_logfile0" 2>/dev/null | tr -d '\000')
    PREFIX=$(echo "$VER_LINE" | awk '{print $1}')
    VER_NUM=$(echo "$VER_LINE" | awk '{print $2}')

    if [ -n "$PREFIX" ] && [ -n "$VER_NUM" ]; then
      MAJOR_MINOR=$(echo "$VER_NUM" | cut -d. -f1-2)

      if [[ "$PREFIX" == "MariaDB" ]]; then
        DETECTED_TAG="$MAJOR_MINOR"
      elif [[ "$PREFIX" == "MySQL" ]]; then
        case "$MAJOR_MINOR" in
          5.5) DETECTED_TAG="5.5" ;;
          5.6) DETECTED_TAG="10.0" ;;
          5.7) DETECTED_TAG="10.1" ;;
          8.0) DETECTED_TAG="10.4" ;;
          *)   DETECTED_TAG="" ;;
        esac
      fi
    fi
  fi

  # Fallback: mysql_upgrade_info (if present)
  if [ -z "$DETECTED_TAG" ] && [ -f "$DATA_DIR/mysql_upgrade_info" ]; then
    UPG_VER=$(cat "$DATA_DIR/mysql_upgrade_info" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -n "$UPG_VER" ]; then
      DETECTED_TAG="$UPG_VER"
    fi
  fi

  if [ -n "$DETECTED_TAG" ]; then
    VERSION="$DETECTED_TAG"
    echo -e "${GREEN}Auto-detected compatible MariaDB tag: $VERSION${RESET}"
  else
    echo -e "${RED}Could not auto-detect version from data directory. Specify --version <tag> to continue.${RESET}"
    exit 1
  fi
else
  VERSION="$USER_VERSION"
  echo -e "${GREEN}Using user-specified version: $VERSION${RESET}"
fi

echo -e "${GREEN}Using data directory: $DATA_DIR${RESET}"
echo -e "${GREEN}Using dumps directory: $DUMPS_DIR${RESET}"
echo -e "${GREEN}Using InnoDB force recovery level: $USER_RECOVERY${RESET}"
if [ -n "$USER_DB" ]; then
  echo -e "${YELLOW}Dumping only specific database: $USER_DB${RESET}"
  if [ -n "$USER_SKIP_TABLES" ]; then
    echo -e "${YELLOW}Skipping tables: $USER_SKIP_TABLES${RESET}"
  fi
elif [ -n "$USER_TABLE" ]; then
  echo -e "${YELLOW}Dumping only specific table: $USER_TABLE${RESET}"
fi
if [ -n "$USER_MYSQLDUMP_ARGS" ]; then
  echo -e "${GREEN}Using mysqldump args: $USER_MYSQLDUMP_ARGS${RESET}"
fi
if [ -n "$USER_MARIADB_ARGS" ]; then
  echo -e "${GREEN}Using mariadb args: $USER_MARIADB_ARGS${RESET}"
fi
if [ -n "$USER_NOCOMPRESS" ]; then
  echo -e "${GREEN}Dumping without compression (.sql files)${RESET}"
fi

# === RUN THE ONE-SHOT CONTAINER (no password env needed) ===
docker run --rm \
  -e INNODB_FORCE_RECOVERY="$USER_RECOVERY" \
  -e SPECIFIC_DB="$USER_DB" \
  -e SKIP_TABLES="$USER_SKIP_TABLES" \
  -e SPECIFIC_TABLE="$USER_TABLE" \
  -e MYSQLDUMP_ARGS="$USER_MYSQLDUMP_ARGS" \
  -e MARIADB_ARGS="$USER_MARIADB_ARGS" \
  -e NOCOMPRESS="$USER_NOCOMPRESS" \
  -v "$DATA_DIR":/var/lib/mysql \
  -v "$DUMPS_DIR":/dumps \
  -v "$(pwd)/dump.sh":/dump.sh \
  mariadb:"$VERSION" \
  /bin/sh /dump.sh

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${GREEN}Process completed successfully. Dumps are in $DUMPS_DIR.${RESET}"
else
  echo -e "${RED}Process failed (likely startup issue). No dumps created.${RESET}"
fi

exit $EXIT_CODE
