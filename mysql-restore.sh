#!/bin/bash

# MySQL Database Restore Script

# Check if required parameters are provided
if [ $# -lt 3 ]; then
  echo "Usage: $0 <database_name> <backup_directory> <log_file>"
  echo "Example: $0 vanga ~/backups ~/mysqldump.restore.log"
  exit 1
fi

# Required parameters
DATABASE="$1"
BACKUP_DIRECTORY="$2"
LOG_FILE="$3"

# Validate parameters
if [ -z "$DATABASE" ] || [ -z "$BACKUP_DIRECTORY" ] || [ -z "$LOG_FILE" ]; then
  echo "Error: All parameters must be non-empty"
  exit 1
fi

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

# Function to list available backups
list_backups() {
  echo "Available backups:"
  find "$BACKUP_DIRECTORY" -name "*$DATABASE*.sql.zst" | sort -r | nl
}

# Restore function
perform_restore() {
  # Check if backup file is provided
  if [ $# -eq 0 ]; then
    echo "Please provide a backup file or choose from the list:"
    list_backups
    return 1
  fi

  local start_time=$(date +%s)

  local BACKUP_FILE=""

  # try to find the backup fiel.
  BACKUP_FILE=$(find "$BACKUP_DIRECTORY" -name "*$DATABASE*.sql.zst" -printf '%T@ %p\n' | sort -nr | awk '{print $2}' | head -n 1)

  # Validate backup file exists
  if [ ! -f "$BACKUP_FILE" ]; then
    error_exit "Backup file not found: $BACKUP_FILE"
  else
    log "Using $BACKUP_FILE to restore $DATABASE."
  fi

  # Create temporary uncompressed SQL file
  local TEMP_SQL_FILE=$(mktemp)

  # Make sure temp file is removed on exit, even if the script fails
  trap 'rm -f "$TEMP_SQL_FILE"' EXIT

  # Decompress the backup
  log "Decompressing backup: $BACKUP_FILE"
  zstd --quiet --force --keep --decompress "$BACKUP_FILE" -o "$TEMP_SQL_FILE" || error_exit "Decompression failed"

  # Drop existing database
  log "Dropping existing database: $DATABASE"
  mysql -e "DROP DATABASE IF EXISTS $DATABASE"

  # Create new database
  log "Creating new database: $DATABASE"
  mysql -e "CREATE DATABASE $DATABASE"

  log "Disabling keys for database: $DATABASE"
  mysql -e "SET foreign_key_checks = 0; SET unique_checks = 0;" || error_exit "Failed to disable keys"

  # Restore database
  log "Restoring database from backup"
  sed -i 's/DEFINER=`bhima`@`localhost`//g' "$TEMP_SQL_FILE"
  mysql "$DATABASE" <"$TEMP_SQL_FILE" || error_exit "Database restoration failed"

  # Enable keys
  log "Enabling keys for database: $DATABASE"
  mysql -e "SET foreign_key_checks = 1; SET unique_checks = 1;" || error_exit "Failed to enable keys"

  # Remove temporary file
  rm "$TEMP_SQL_FILE"
  
  # end time
  local end_time=$(date +%s)

  # duration in seconds
  local duration=$((end_time - start_time))

  # Calculate minutes and seconds
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))

  # Get database statistics to help inform how fresh the data is.
  MAX_CASH_DATE=$(mysql -D "$DATABASE" -N -e "SELECT MAX(date) FROM cash;")
  MAX_INVOICE_DATE=$(mysql -D "$DATABASE" -N -e "SELECT MAX(date) FROM invoice;")
  MAX_VOUCHER_DATE=$(mysql -D "$DATABASE" -N -e "SELECT MAX(date) FROM voucher;")
  
  # Update the dashboard to denote when the database was last build
  SIZE=$(mysql -sN -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) FROM information_schema.tables WHERE table_schema = '$DATABASE';")
  MSG="Database last built at $(date +"%Y-%m-%d %H:%M:%S %Z").
    It is currently $SIZE MB in size.
    Lastest Invoice: $MAX_INVOICE_DATE.
    Lastest Cash Payment: $MAX_CASH_DATE.
    Lastest Voucher: $MAX_VOUCHER_DATE.
    The database build process took ${minutes}m${seconds}s."

  mysql $DATABASE -e "UPDATE enterprise SET helpdesk='$MSG';"

  log "Database restore completed successfully in ${minutes}m${seconds}s"
}

# Interactive restore selection
interactive_restore() {
  list_backups
  read -p "Enter the number of the backup to restore (or full path to backup file): " selection
  perform_restore "$selection"
}

# Help function
show_help() {
  echo "Usage:"
  echo "  $0 [backup_file]     Restore from a specific backup file"
  echo "  $0 -i, --interactive Interactive backup selection and restore"
  echo "  $0 -l, --list        List available backups"
}

# Main script logic
case "$1" in
-h | --help)
  show_help
  ;;
-l | --list)
  list_backups
  ;;
-i | --interactive)
  interactive_restore
  ;;
"")
  interactive_restore
  ;;
*)
  perform_restore "$1"
  ;;
esac
