# R4b implementation

R4b tests one frozen lifecycle boundary: a new qcrild2 native producer epoch, followed by a new persistent `.qtidataservices` provider epoch, followed by a new `com.android.phone` consumer epoch. It preserves the proven R0, R3, fixed-P and hash-locked v2.6.2 implementations.

The provider primitive is one `TERM` to the dynamically selected, fully verified `.qtidataservices` PID. The gate requires UID 10104, the audited SELinux domain, zygote parent, ActivityManager `PERS` record and the expected shared package group. There is no package force-stop, fuzzy kill, second TERM or SIGKILL fallback.

The fixed order is:

`R0 -> R0_NATIVE_READY -> qcrild2 cold epoch -> PRODUCER_READY -> qtidataservices cold epoch -> PROVIDER_READY -> R3 -> A_READY -> fixed P -> hash-locked v2.6.2 -> WFC`.

The one reboot belongs only to `CONTROL_A0_R4B_V1`. No reboot is permitted between cycles. A valid failure terminates the series.

