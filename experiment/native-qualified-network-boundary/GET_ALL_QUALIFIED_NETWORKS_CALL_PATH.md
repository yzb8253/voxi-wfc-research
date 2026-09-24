# Target-ROM `getAllQualifiedNetworks` call path

Date: 2026-09-24
Starting commit: `f091a094fbf991e7a4c4e7ce9fc390fa17257c01`
Method: target-ROM binary inspection plus preserved R4b logs
Phone writes: **0**

## Target artifact

- Binary: `/vendor/lib64/libril-qc-hal-qmi.so`
- Host-side exact copy size: `34938552` bytes
- SHA-256: `33A36EBCE79435B06A1BEDDC09B9B6D8A3B6D082D9ACF7624A883FBAEC8EDE77`
- The relevant C++ symbols are present in the target binary; the mapping below does not rely only on public source.

## Native request path

1. `vendor::qti::hardware::data::iwlan::IWlanImpl::getAllQualifiedNetworks(int)` at `0x161c360` constructs `rildata::GetAllQualifiedNetworkRequestMessage`, attaches a `GenericCallback`, and dispatches it into qcrild2's DataModule thread.
2. `rildata::DataModule::handleGetAllQualifiedNetworksMessage(std::shared_ptr<Message>)` at `0x156dbac` accepts the request only after its DataModule/readiness gates pass and a `NetworkAvailabilityHandler` exists.
3. The handler calls `rildata::NetworkAvailabilityHandler::getQualifiedNetworks(std::vector<QualifiedNetwork_t>&)` at `0x1630600`.
4. `getQualifiedNetworks` iterates the `NetworkAvailabilityHandler` container at object offset `+0x60`, copies every `QualifiedNetwork_t` entry into the response vector, and logs `process get qualified networks` / `Sent qualified networks`.
5. DataModule wraps that vector in `QualifiedNetworkResult_t` and completes the solicited message.
6. The `IWlanImpl` callback passes the exact vector through `IWlanImpl::convertQualifiedNetworksToHAL` at `0x161d004`. The output count equals the input count; APN type and network enum vectors are copied, not re-evaluated.
7. The existing HIDL callback receives `IIWlanResponse::getAllQualifiedNetworksResponse(serial, result)`.
8. In `vendor.qti.iwlan`, `IWlanResponse` resolves the serial through `IWlanProxy`'s request table. `NetworkAvailabilityProviderImpl` calls `updateQualifiedNetworkTypes(...)` for returned entries and then registers for future qualified-network changes.

## Native request gates

Before the cache lookup, the DataModule handler verifies its initialized state, the relevant Auth/DSD/WDS/IWLAN readiness booleans, and a non-null `NetworkAvailabilityHandler`. These are request-level availability gates. Once the handler calls `getQualifiedNetworks`, the response is a direct copy of the current `+0x60` container.

No GET-path filtering was found for slotId, phoneId, subId, IMS APN, Wi-Fi availability, airplane mode, SIM/UICC state, PS registration, data-allowed state, preferred system, MCCMNC/carrier, DDS, emergency state, RAT, or generation/session ID. Such inputs can affect how the upstream NAH caches are built, but they are not a second filtering pass in this query.

## Serial 0 reconstruction

| Stage | Evidence | Result |
|---|---|---|
| REQUEST_ACCEPTED | `21:41:35.018051 0 > REQUEST_GET_QUALIFIED_NETWORKS` | YES |
| HANDLER_ENTER | target NAH log `21:41:35.072 process get qualified networks` | YES |
| CACHE_LOOKUP | static handler trace: same `+0x60` container shown as `LastReportedNetworkAvailability` | YES |
| CACHE_SIZE | current dump has no `LastReportedNetworkAvailability` entries; Java response is blank | 0 |
| FILTER_INPUT / FILTER_OUTPUT | no query filtering stage exists | N/A |
| RESPONSE_BUILD | solicited `QualifiedNetworkResult_t`, vector length 0 | YES |
| RESPONSE_COUNT | exact Java formatter produced no entry text | 0 |
| CALLBACK_SEND | `21:41:35.074693 getAllQualifiedNetworksResponse`, then serial processed | YES |

The Java request was queued about 30 ms before the new native NAH constructor (`21:41:35.048`), but native handling occurred 24 ms after construction. The query therefore reached a valid, newly created handler whose published/current result container was still empty.

## Serial 6 reconstruction

| Stage | Evidence | Result |
|---|---|---|
| REQUEST_ACCEPTED | `21:43:28.507416 6 > REQUEST_GET_QUALIFIED_NETWORKS` | YES |
| HANDLER_ENTER | per-serial native line not retained | UNOBSERVABLE |
| CACHE_LOOKUP | fixed native call path; no alternative query source exists | STATICALLY YES, runtime line UNOBSERVABLE |
| CACHE_SIZE | blank exact Java response | 0 |
| FILTER_INPUT / FILTER_OUTPUT | no query filtering stage exists | N/A |
| RESPONSE_BUILD | normal response completed | YES |
| RESPONSE_COUNT | blank exact Java formatter | 0 |
| CALLBACK_SEND | `21:43:28.508412`, then serial processed | YES |

No third NAH constructor or fresh current-generation publication occurred between serial 0 and serial 6. The narrowest explanation is that the same new NAH generation's `LastReportedNetworkAvailability` remained empty, so the fresh new-phone provider correctly received zero entries again.

## Boundary conclusion

The target implementation does not support a hidden query cache or a lossy GET response filter. The real boundary is earlier:

`new initializeIWLAN/NAH generation -> populate working cache -> publish LastReportedNetworkAvailability -> initial GET`.

In R4b, the initial GET ran after NAH construction but before the new generation had populated/published a result.
