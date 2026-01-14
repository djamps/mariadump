# Offline MariaDB Dump Tool

## Overview

Creates a one-shot MariaDB docker container that starts MariaDB, waits for it to be ready (handling failures), dumps each qualifying database found in the specified data folder (excluding `mysql`, `information_schema`, and `performance_schema`) to a file(s), then exits.  No root password is required, since the server starts in recovery mode (`--skip-grant-tables`).

This tool is handy for crash recovery (primary DB won't start), upgrades (iterate over many versions), or extracting SQL data from filesystem backups.

## Warning

Use only on a copy/backup of your data folder.   Damage to database can occur if used on a live data folder.   You can use tools such as mariadb-backup to make a copy of your live/running database, or shut down the server and copy the data manually.

## Prerequisites

- Linux or WSL on Windows.
- Docker installed and running (the tool will check and report if not available).
- Both scripts (`dump.sh` and `run.sh`) in your working directory.
- MySQL/MariaDB data in `./mysql` (relative to current directory, override with --data-dir; paths are validated for security).
- The minimum files/folders inside the data folder required to run the container are: `mysql` (database), `ibdata1`, `ib_logfile*`, and at least one database folder.

## Notes

- You can remove/omit non-interesting database folders (except `mysql`) to speed up recovery.
- The script pulls the official MariaDB docker image with version auto-detected or manually specified (`--version`).
- Version auto-detection works for MySQL 5.5+ (maps to compatible MariaDB tags like 5.5 for MySQL 5.5, 10.0 for MySQL 5.6) and native MariaDB data, parsing `ib_logfile0` (primary) or `mysql_upgrade_info` (fallback).
- InnoDB force recovery: Optional level 0-6 to handle corrupt data (higher levels allow startup but risk data inconsistency; use cautiously, e.g., start at 1 and increase if needed).

## Options

```
--run                       Create dump files

--list                      List the databases found (does not dump).  
                            Combine with --database <db_name> to list tables.

--version <tag>             Specify MariaDB Docker tag (e.g., 10.3). 
                            If omitted, auto-detects from data.

--recovery <0-6>            Set InnoDB force recovery level (default: 0). 
                            Higher values for corrupt data.

--database <db_name>        Dump only a specific database (overrides full dumps and --table).

--skip-tables <t1,t2>       Comma-separated tables to skip in the database 
                            (only with --database; for skipping corrupt tables).

--table <db.table>          Dump only a specific database table 
                            (overrides full dumps and --database).

--mysqldump-args "--arg1 --arg2"  Pass raw arguments to mysqldump 
                                  (e.g., "--skip-add-drop-table").

--mariadb-args "--arg1 --arg2"    Pass raw arguments to mariadb 
                                  (e.g., "--innodb-buffer-pool-size=1G").

--nocompress                Output plain .sql files instead of .sql.gz.

--dumps-dir                 Custom dumps directory (defaults to ./dumps)

--data-dir                  Custom data directory (defaults to ./mysql)
```

## Examples

```
# Shows help/usage
./run.sh

# Auto-detect version, dump all databases
./run.sh --run

#  Auto-detect version, list all databases
./run.sh --list

#  Auto-detect version, list tables of mydb
./run.sh --database mydb --list

# Auto-detect version, dump single database
./run.sh --database mydb --run

# Auto-detect version, dump single table
./run.sh --table mydb.mytable --run

# Auto-detect version, recovery 4, dump all databases
./run.sh --recovery 4 --run

# Version 10.3, dump all databases
./run.sh --version 10.3 --run

# Auto-detect, dump mydb skipping tables bad1, bad2
./run.sh --database mydb --skip-tables bad1,bad2 --run

# Advanced options
./run.sh --version 10.3 --recovery 2 --database mydb --skip-tables bad1,bad2 \
         --mysqldump-args "--skip-add-drop-table" \
         --mariadb-args "--innodb-buffer-pool-size=1G" \
         --nocompress --run
```

## Instructions for Use

- Navigate to your working directory containing the scripts (make sure your data folder is in the same working directory called `mysql`.
- Execute `run.sh` referencing the examples provided
- If no errors, check `./dumps` for the dump files

## Additional notes

The container runs in the foreground, logging all progress to the console.  It exits automatically.   If anything goes wrong, the reason should be evident on the console.

To run the test suite, ensure Bats is installed (`npm install -g bats`) and execute `bats tests/`.
