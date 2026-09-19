# Fixed-target helper work

No unverified helper binary is checked in yet.

The preferred next helper is a reflection-based `Slot1SimPowerHelper` with exactly four commands:

- `dry-run`: prove UID 0, target slot 1 identity, protected slot0 identity, and current card state.
- `power-down`: invoke only `TelephonyManager.setSimPowerStateForSlot(1, POWER_DOWN)`.
- `power-up`: invoke only `TelephonyManager.setSimPowerStateForSlot(1, POWER_UP)`.
- `status`: read callback/result state without a write.

Before building it, static analysis must prove the constants on this ROM, `PhoneInterfaceManager` slot semantics, `CommandsInterface` routing to Radio `slot2`, callback completion behavior, and the absence of a loop over all phones. The power-down experiment must always schedule an independent power-up rollback path before making the write.

`refreshUiccProfile` and direct `IUim/Uim1` helpers remain lower priority. No raw Binder/HIDL transaction number may be guessed.

