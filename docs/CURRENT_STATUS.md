# Current Status

## Stable reference

The stable reproducibility reference remains Golden commit `dfd82415073470691295547d39753f6172054748` with a historical 6/6 result. The latest commit is a research head, not a replacement baseline.

## Current understanding

The difficult failure boundary is not basic UICC restoration or MMTEL readiness. A run can restore subscription/UICC and MMTEL yet fail to republish a fresh Qualcomm CNE IMS demand. Without that demand, there is no current IMS NetworkRequest, ePDG/XFRM path, WLAN IMS registration or WFC.

The project has narrowed investigation through X55 ownership, RIL/QMI, QNS/IWLAN provider, Android telephony framework and typed/raw UICC transaction experiments. Many larger resets were informative failures rather than fixes.

## Active work

- Reproduce Golden behavior without changing its source.
- Determine the smallest boot-equivalent lifecycle that regenerates a fresh CNE request.
- Compare typed and raw `ISub.setUiccApplicationsEnabled` transactions under a single-variable protocol.
- Preserve conservative wait windows: successful CNE generation has been observed after more than 20 seconds.
- Resolve publication-safety blockers before public visibility.

## Non-goals

- Claiming support for other devices or ROMs.
- Recommending the latest experimental launcher over Golden.
- Adding unproven service restarts, callback injection or periodic QNS re-report workarounds.
- Treating supporting signals as a substitute for direct WFC health.

## Publication status

Documentation and collaboration templates are prepared. Visibility remains private because historical snapshots contain persistent device/network identifiers. See `docs/PUBLICATION_SAFETY_AUDIT.md`.
