# L1.5 executor preparation

This directory contains an audited **execution preparation**, not an executed experiment. No helper or watchdog was deployed to the phone and no SIM-power request was sent while creating it.

Contents:

- `src/Slot1SimPowerHelper.java` — fixed slot1 root helper using the callback overload of `TelephonyManager.setSimPowerStateForSlot`.
- `device/l1_5_rollback_watchdog.sh` — independent device-side 30-second rollback watchdog.
- `run_l1_5_executor.sh` — host orchestrator; defaults to read-only and never deploys files.
- `build_executor.ps1` — reproducible javac/D8 build driver.
- `audit_executor.ps1` — static safety assertions.
- `L1_5_EXECUTION_PLAN.md` — execution sequence, risk and success criteria.
- `CODE_AUDIT.md` — preparation-stage audit result.

## Safety locks

The Java helper accepts no slot, phoneId, subId, transaction number, or numeric power-state argument. Its only RIL write call uses the compile-time constant `TARGET_SLOT_ID=1`. Slot 0 appears only in protected-state verification.

Every write requires both:

```text
LAB_MODE=1
LAB_EXECUTE=YES
```

`LAB_MODE` defaults to `0`; `LAB_EXECUTE` defaults to `NO`. POWER_DOWN additionally requires a same-boot, five-minute rollback arm and a live watchdog-ready marker. The watchdog starts its 30-second deadline only after the helper records `power_down.sent`.

## Preparation-stage validation

```powershell
./audit_executor.ps1
```

```sh
bash -n run_l1_5_executor.sh
bash -n device/l1_5_rollback_watchdog.sh
```

Building requires an audited JDK and Android D8 toolchain supplied explicitly through `JAVAC` and `D8`. The generated `build/` directory is ignored and must not be deployed until its hash and source revision have been reviewed.
