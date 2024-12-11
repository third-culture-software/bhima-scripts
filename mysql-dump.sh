#!/bin/bash

# Enhanced MySQL Database Backup Script

# Check if required parameters are provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 <database_name> [backup_directory] [log_file] [max_backups] [compression_level]"
  echo "Example: $0 vanga ~/backups ~/mysqldump.backup.log 14 22"
  exit 1
fi
# Required parameters
DATABASE="$1"

# Optional parameters with defaults
BACKUP_DIRECTORY="${2:-$HOME/backups}"
LOG_FILE="${3:-$HOME/mysqldump.backup.log}"
MAX_BACKUPS="${4:-14}"       # Keep two weeks of backups by default
COMPRESSION_LEVEL="${5:-15}" # Default compression level 15

# Validate parameters
if [ -z "$DATABASE" ]; then
  echo "Error: Database name, backup directory, and log file must be non-empty"
  exit 1
fi

# Ensure backup directory exists
mkdir -p "$BACKUP_DIRECTORY"

# Logging function
log() {
  local message="$1"
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $message" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
  local message="$1"
  log "ERROR: $message" >&2
  exit 1
}

# Backup function
perform_backup() {

  # Generate output filename with more precise timestamp
  local OUTFILE="$BACKUP_DIRECTORY/$DATABASE-$(date +"%Y-%m-%d-%H-%M-%S").sql"

  # Perform mysqldump with comprehensive options
  log "Starting backup of database: $DATABASE, compression level: $COMPRESSION_LEVEL."
  mysqldump \
    --add-drop-database \
    --add-drop-table \
    --column-statistics=0 \
    --complete-insert \
    --disable-keys \
    --events \
    --extended-insert \
    --hex-blob \
    --no-tablespaces \
    --quick \
    --routines \
    --set-gtid-purged=OFF \
    --single-transaction \
    --skip-lock-tables \
    --triggers \
    --tz-utc \
    "$DATABASE" >"$OUTFILE" || error_exit "mysqldump failed"

  # Remove definer statements to improve portability
  sed -i 's/DEFINER=[^*]*\*/\*/g' "$OUTFILE"

  # Compress with zstd for better compression and speed
  zstd --quiet --ultra -"$COMPRESSION_LEVEL" "$OUTFILE" || error_exit "Compression failed"
  rm "$OUTFILE" # Remove uncompressed file after compression

  log "Backup completed successfully: ${OUTFILE}.zst"
}

# Cleanup old backups
cleanup_old_backups() {
  log "Cleaning up old backups"
  # Find and remove backups older than MAX_BACKUPS days
  find "$BACKUP_DIRECTORY" -name "*.sql.zst" -mtime +"$MAX_BACKUPS" -delete
}

# Main execution
main() {
  # Trap to ensure cleanup happens even if script is interrupted
  trap 'log "Backup process interrupted"' SIGINT SIGTERM

  perform_backup
  cleanup_old_backups

  log "Backup process completed successfully"
}

# Run the main function
main
