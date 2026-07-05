# GymOfflineSystem

## Atomic JSON Save Recovery

All core JSON data files in the `Data` folder are now saved through `JsonFileService` using an atomic write flow:

1. New JSON is written to `Data/filename.json.tmp`.
2. Existing `Data/filename.json` is renamed to `Data/filename.json.bak`.
3. The temp file is renamed to `Data/filename.json`.
4. The `.bak` file is deleted after the swap succeeds.

This protects the real file from partial writes during power loss, crashes, or interrupted saves.

## Automatic Recovery Rules

- If the app starts and `Data/filename.json` is missing but `Data/filename.json.bak` exists, the backup is restored automatically.
- If the main `Data/filename.json` file exists but is corrupt, the service tries to recover from `.bak` first.
- Any leftover `Data/filename.json.tmp` file from an interrupted save is cleaned up automatically before reads continue.
- Snapshot copies are also stored in `Data/Backup` as an extra recovery layer.
- This recovery check runs automatically at application startup for all core configuration, client, payment, and attendance files.

## Manual Verification Checklist

You can test the recovery flow with any data file such as `Data/clients.json`:

1. Run the app and create or edit data normally.
2. Confirm the main JSON file updates correctly.
3. Simulate a failed save by temporarily renaming `clients.json` to `clients.json.bak` and removing `clients.json`.
4. Start the app again.
5. Confirm the service recreates `clients.json` from `clients.json.bak`.
6. To test corrupt-file recovery, put invalid JSON into `clients.json` and keep a valid `clients.json.bak`.
7. Start the app and confirm the valid backup is restored.

If recovery happens, details are logged in `Logs/error_log.txt`.
