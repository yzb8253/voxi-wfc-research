# Phase authorization and guardrails

The project goal for this phase is to reproduce the event chain of physical VOXI SIM removal/insertion without rebooting the Android AP. The user explicitly allows aggressive reversible telephony, RIL and vendor experiments, while continuing to forbid AP reboot, boot modification, flashing and permanent dual-SIM damage.

This authorization does not make every candidate safe or approved. Each script remains opt-in, fixed-target and individually gated. Unknown raw Binder/HIDL/QMI calls remain blocked until their current-ROM method, arguments, slot mapping, handler and rollback are statically proven. An experiment failure never falls through to a higher level.

EFS, NV, QCN, PDC/MBN, persist, firmware and SIM/eSIM provisioning writes remain outside the lab.

