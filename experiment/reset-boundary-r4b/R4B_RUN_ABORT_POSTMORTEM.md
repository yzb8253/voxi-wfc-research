# R4b v1 provider-adapter abort

The approved series performed the baseline reboot, one qcrild2 producer reset and one exact `.qtidataservices` TERM. It then stopped inside the provider evidence adapter before a readiness verdict.

Exact exception: Windows PowerShell 5.1 strict mode `PropertyNotFoundStrict: The property 'Count' cannot be found on this object.` The first matching new-PID log line made `New-PidLine` return a scalar string, while the caller assumed an array and accessed `.Count`.

The correction wraps all calls as `@(New-PidLine ...).Count`. The static audit now rejects any reintroduced unwrapped form. This changes observation plumbing only; reset order, count, gates, timeout, P, v2.6.2 and recovery semantics are unchanged.

The current series cannot be resumed: its one provider TERM was consumed and its evidence gate terminated. A future execution would require a separately approved new baseline and series. No such execution occurred here.
