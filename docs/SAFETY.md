# Safety

## Scope

These tools can change external-modem ownership, signal native processes and modify SIM/UICC state. They were developed for one rooted Xiaomi Mi 10 ROM. Do not use them as generic Android repair scripts.

## Non-negotiable gates

- Exact device/ROM and target subscription mapping.
- Root identity and expected SELinux/process identity.
- Exact PID, executable, command line and FD ownership where required.
- Unambiguous X55 state and legal crash count.
- Current connectivity table for write-decision CNE state; historical request logs are diagnostic only.
- Bounded write count and verified rollback.
- Fail closed on missing, stale, conflicting or unparsable evidence.

## Write boundaries

Every experiment must enumerate its allowed writes before execution. Writes not listed in that contract are forbidden. Never improvise a second SIM cycle, service restart, modem reset, airplane toggle or process kill after failure.

## UICC rollback

Any flow that disables target UICC applications must guarantee one bounded re-enable attempt if the normal path does not complete. It must never write another slot/subscription. Section-aware current subscription parsing is required; historical `dumpsys isub` event lines are not authoritative.

## Native ownership

Do not signal by name, use `killall`, or guess a PID. Verify the exact live process and `/dev/subsys_esoc0` owner. Do not use `SIGKILL` where the audited protocol specifies TERM and cleanup.

## Emergency and service risk

Experiments can interrupt both SIMs, mobile data, IMS and emergency calling. Use a separate reliable communications path. Never test when emergency availability is required.

## Data safety

Raw captures can contain persistent device IDs, account-like tags, ADB serials, phone/SIM identifiers, MAC/BSSID, SSIDs, IP addresses, VPN details and local usernames. Redact before sharing and run the publication audit. Do not assume a Git deletion removes data from history.
