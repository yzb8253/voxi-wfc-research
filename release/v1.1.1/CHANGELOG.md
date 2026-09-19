# Changelog

## v1.1.1

- Removed the Toybox-incompatible `exec 9>` / `flock -n 9` lock path.
- Unified recovery locking on an atomic `mkdir` lock directory.
- Added per-process lock ownership tracking so cleanup removes only a lock acquired by the current script.
- Kept all Telephony writes, recovery state transitions, health rules, and safety gates unchanged.

## v1.1

- Added manual, F1-only Deep Recover with one false call, mandatory F8 confirmation, and one true call.
- Kept Magisk Action conservative: healthy is zero-write and F1 only displays the manual command.
- Updated direct health to REGISTERED + WLAN + VOICE/IWLAN + WFC availability.
- Reclassified IMS NetworkAgent and other data-path observations as supporting evidence.
