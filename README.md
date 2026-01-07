# Offline MariaDB Dump Tool

## Overview

Automates the dumping of MySQL/MariaDB databases or tables from an offline data folder using a temporary MariaDB Docker container. It creates a one-shot container that starts MariaDB in the background, waits for it to be ready (handling failures), dumps each qualifying database (excluding `mysql`, `information_schema`, and `performance_schema`) to a SQL file(s) in `./dumps`, and then exits.  No root password is required, since the server starts in recovery mode (`--skip-grant-tables`) to bypass authentication and prevent writes.   

This tool is most useful for crash recovery (primary DB won't start), migrations, or extracting databases from filesystem backups.

## Warning

Use only on a copy/backup of your data folder.   Damage to database can occur if used on a live data folder.   You can use tools such as mariadb-backup to make a copy of your live/running database, or shut down the server and copy the data manually.

## Prerequisites

- *Nix host (Cygwin or docker shell on Windows might work but is not tested)
- Docker installed and running.
- Place both scripts (`dump.sh` and `run.sh`) in your working directory.
- Your MySQL/MariaDB data is in `./mysql` (relative to current directory, override with --data-dir).
- The minimum files/folders inside the data folder required to run the container are: `mysql` (database), `ibdata1`, `ib_logfile*`, and at least one database folder.

## Notes

- You can remove/omit database folders that you do not wish to dump to speed up recovery.   But the `mysql` database folder is always required.
- The script pulls the official MariaDB docker image with version auto-detected or manually specified.
- Version auto-detection works for MySQL 5.5+ (maps to compatible MariaDB tags like 5.5 for MySQL 5.5, 10.0 for MySQL 5.6) and native MariaDB data, parsing `ib_logfile0` (primary) or `mysql_upgrade_info` (fallback).
- InnoDB force recovery: Optional level 0-6 to handle corrupt data (higher levels allow startup but risk data inconsistency; use cautiously, e.g., start at 1 and increase if needed).

## Options

```
--version <tag>             Specify MariaDB Docker tag (e.g., 10.3). If omitted, auto-detects from data.
--recovery <0-6>            Set InnoDB force recovery level (default: 0). Higher values for corrupt data.
--database <db_name>        Dump only a specific database (overrides full dumps and --table).
--skip-tables <t1,t2>       Comma-separated tables to skip in the database (only with --database; for corrupt tables).
--table <db.table>          Dump only a specific database table (overrides full dumps and --database).
--mysqldump-args "--arg1 --arg2"  Pass raw arguments to mysqldump (e.g., "--skip-add-drop-table").
--mariadb-args "--arg1 --arg2"  Pass raw arguments to mariadb (e.g., "--innodb-buffer-pool-size=1G").
--nocompress                Output plain .sql files instead of .sql.gz.
--dumps-dir                 Custom dumps directory (defaults to ./dumps)
--data-dir                  Custom data directory (defaults to ./mysql)
```

## Examples

```
# Shows help/usage
./run.sh

# Auto-detect version, recovery 0, all databases
./run.sh --run

# Auto-detect version, recovery 0, single database
./run.sh --database mydb --run

# Auto-detect version, recovery 0, single table
./run.sh --table mydb.mytable --run

# Auto-detect version, recovery 4, all databases
./run.sh --recovery 4 --run

# Version 10.3, recovery 0, all databases
./run.sh --version 10.3 --run

# Auto-detect, recovery 0, mydb skipping bad1/bad2
./run.sh --database mydb --skip-tables bad1,bad2 --run

# All relevant options
./run.sh --version 10.3 --recovery 2 --database mydb --skip-tables bad1,bad2 --mysqldump-args "--skip-add-drop-table" --nocompress --run
```

## Instructions for Use

- Navigate to your working directory containing the scripts (make sure your data folder is in the same working directory called `mysql`.
- Execute `run.sh` using the examples provided
- If no errors, check `./dumps` for the dump files

## Additional notes

The container runs in the foreground, logging all progresses to the console.  It exits automatically.   If anything goes wrong, the reason should be evident on the console.
