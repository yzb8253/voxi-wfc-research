# Known Results

| Experiment/result | Evidence-based conclusion | Classification |
| --- | --- | --- |
| Golden stable wrapper | 6/6 historical controlled successes on the original platform | GOLDEN |
| UICC `false -> F8 -> true` | Repeated historical association with fresh CNE requests; exact observer/transaction details matter | STABLE evidence, device-specific |
| `resetIms(1)` | Did not recover the preserved Active+Enabled F1 scene | HISTORICAL negative result |
| IMS/CNE/userspace restarts | Multiple scoped and full userspace rebuilds failed to regenerate demand in the preserved scene | HISTORICAL negative result |
| `system_server` restart | Rebuilt framework objects and preferred state, but no new native IMS demand | HISTORICAL negative result |
| Coordinated RIL-pair recovery | Restored RIL/QtiBus and replayed IMSS state; WFC recovery remained unproven/failed in that scene | HISTORICAL negative result |
| Modem SSR | Standard trigger was not verified on the ROM; unsafe guessed interfaces were not used | NOT EXECUTED |
| R3 framework reset | One valid single-cycle pass; an early second-cycle abort was an orchestrator gate bug, not falsification | EXPERIMENTAL |
| R4b provider reset | Falsified at the documented lifecycle/preparation boundary | EXPERIMENTAL negative result |
| QNS cache snapshots | Bad F1 showed IMS/default/eims entries with empty qualified-network lists despite global IWLAN preference | PROFILING evidence |
| Current-table CNE parser | Fixed false “active” reports caused by scanning historical release logs | STABLE parser result |
| FAST holder | Reduced FD-owner release latency from sleep-cycle behavior | STABLE mechanism result |
| OLD vs FAST holder | No current evidence that holder implementation determines WFC success | INCONCLUSIVE |
| Golden Simple typed/raw UICC transaction | Controlled comparison remains under investigation | EXPERIMENTAL |

## Interpretation limits

These results apply to the recorded device/ROM and exact state. A failed recovery action can still be useful as a boundary result. A successful run does not prove causality unless the experiment changed only one controlled variable.
