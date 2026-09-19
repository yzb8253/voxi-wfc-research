# Current Project Status

## Active phase: SIM soft-reset matrix

On 2026-09-19 the project moved from generic IMS process recovery to reproducing the event chain of physical VOXI SIM removal/insertion without rebooting Android. The matrix and opt-in scripts are under `experiments/sim_soft_reset/`.

Read-only live inventory on serial `192.168.1.25:42319` confirmed root, both qcrild services, standard `IRadio/slot1` and `IRadio/slot2`, Qualcomm `IUim/Uim0` and `IUim/Uim1`, and current active/enabled F1. An L0 baseline successfully captured full before/after state and logcat without a phone write. Raw run data remains local and is Git-ignored.

The preferred next candidate is a fixed slot1 `setSimPowerStateForSlot` power-down/up helper, but it is intentionally blocked until its current-ROM framework -> Radio HAL -> qcrild2 -> QMI UIM path, constants, callback and rollback are statically proven. No SIM/UICC/RIL/modem write was executed while building the matrix.

Read-only slot mapping is now complete: VOXI is Android slot/phone 1, Radio HAL `IRadio/slot2`, Qualcomm `IUim/Uim1`, `vendor.qcrild2 -c 2`, modem stack 1. China Telecom is Android slot/phone 0, `IRadio/slot1`, `IUim/Uim0`, primary qcrild, stack 0. See `experiments/sim_soft_reset/SLOT_MAPPING/VOXI_SLOT_MAPPING.md`. SIM-power execution remains blocked.

## Purpose
This repository is the cross-account handoff point for the VOXI Wi-Fi Calling research project. A new Codex session should read `AGENTS.md`, `README.md`, `STATUS.md`, `VALIDATION_REPORT.md`, `FINAL_RUNBOOK.md`, and the files under `autopilot/` before proposing new experiments.

## Validated result
The inactive-subscription F8 recovery path was validated 3/3:
- VOXI target: subId 11 / slot 1 / phoneId 1 / carrierId 28 / MCCMNC 23415.
- Protected slot0: China Telecom subId 1 / MCCMNC 46011.
- Recovery from verified inactive/apps-disabled F8 uses exactly one fixed `ISub.setUiccApplicationsEnabled(true,11)` after safety gates pass.
- The three validation cycles reached GOLDEN_STRONG in 10 s, 18 s, and 37 s respectively and remained healthy for about 300 s.
- Healthy and active-but-unhealthy states receive no automatic write.

## Active/enabled F1 investigation
A separate active/enabled F1 failure was investigated extensively. The saved audit shows that the following did not restore IMS/WFC:
- one `ITelephony.resetIms(1)` test;
- restart of `org.codeaurora.ims`;
- restart of `.qtidataservices` / CNE + IWLAN services;
- restart of `vendor.cnd`;
- coordinated cnd + CNE restart;
- later no-reboot experiments involving imsdatadaemon, imsqmidaemon, com.android.phone, and a broader soft-stack reconstruction.

The final no-reboot investigation concluded that no recovery path had been found above the modem/SSR boundary. Do not repeat these failed sequences unless the environment or hypothesis materially changes.

## Imported evidence
The repository now contains:
- project rules and resume protocol in `AGENTS.md`;
- root README, validation report, and final runbook;
- cycle-1 recovery timeline;
- final runbook under `autopilot/`;
- command audit and structured experiment history.

The original local ZIP contains much more raw capture data. Large logs, APK/JAR/DEX dumps, nested Git metadata, and generated binaries are intentionally not being treated as normal source files for the shared repository.

## Cross-account workflow
At the end of each meaningful Codex session:
1. update this file with the current state;
2. record new successful/failed experiments in the audit/history;
3. commit source/documentation changes;
4. push them to this private repository.

A second ChatGPT/Codex account can then continue by opening this same repository and reading the handoff files instead of relying on chat history.
