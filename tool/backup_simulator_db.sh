#!/bin/sh
# Copy or inspect the iPhone simulator VAXtrust database.
# This script only reads the simulator file and writes a new copy.
# It does not uninstall the app, erase the simulator, migrate the schema,
# or modify the database that the app is using.
#
# Choose a simulator with VAXTRUST_SIMULATOR_UDID.
# When that variable is unset, the script uses the single booted simulator.

set -eu

bundle_id="com.vaxtrust.vaxtrust"

usage() {
  echo "Usage: tool/backup_simulator_db.sh status"
  echo "       tool/backup_simulator_db.sh copy <new-file.db>"
  echo "The copy destination must be a path that does not already exist."
  echo "Set VAXTRUST_SIMULATOR_UDID to choose a simulator. Otherwise the single booted simulator is used."
}

resolve_udid() {
  if [ -n "${VAXTRUST_SIMULATOR_UDID:-}" ]; then
    printf '%s\n' "$VAXTRUST_SIMULATOR_UDID"
    return
  fi

  booted=$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-Fa-f]\{8\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{12\}\)) (Booted).*/\1/p')
  count=0
  if [ -n "$booted" ]; then
    count=$(printf '%s\n' "$booted" | wc -l | tr -d ' ')
  fi
  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$booted"
    return
  fi

  echo "Set VAXTRUST_SIMULATOR_UDID to a simulator UDID, or boot exactly one simulator." >&2
  exit 1
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

udid=$(resolve_udid)
container=$(xcrun simctl get_app_container "$udid" "$bundle_id" data)
source_db="$container/Documents/vaxtrust.db"

if [ ! -f "$source_db" ]; then
  echo "Simulator database was not found: $source_db" >&2
  exit 1
fi

report() {
  sqlite3 "file:$1?mode=ro" <<'SQL'
PRAGMA query_only = ON;
.headers off
.mode list
SELECT 'schema', user_version FROM pragma_user_version;
SELECT 'users', COUNT(*) FROM users;
SELECT 'shipments', COUNT(*) FROM shipments;
SELECT 'temperature_readings', COUNT(*) FROM temperature_readings;
SELECT 'temperature_excursions', COUNT(*) FROM temperature_excursions;
SELECT 'quality_reviews', COUNT(*) FROM quality_reviews;
SELECT 'excursion_actions', COUNT(*) FROM excursion_actions;
SELECT 'shipment_releases', COUNT(*) FROM shipment_releases;
SELECT 'shipment_receipts', COUNT(*) FROM shipment_receipts;
SQL
}

case "$1" in
  status)
    echo "source=$source_db"
    report "$source_db"
    ;;
  copy)
    if [ "$#" -ne 2 ]; then
      usage
      exit 1
    fi
    destination=$2
    if [ -e "$destination" ] || [ -e "$destination-wal" ] || [ -e "$destination-shm" ]; then
      echo "Refusing to overwrite an existing file: $destination" >&2
      exit 1
    fi
    destination_dir=$(dirname "$destination")
    mkdir -p "$destination_dir"
    sqlite3 "file:$source_db?mode=ro" ".backup '$destination'"
    echo "copied=$destination"
    report "$destination"
    ;;
  *)
    usage
    exit 1
    ;;
esac
