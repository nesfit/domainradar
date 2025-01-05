# Collectors & models

The main pipeline consists of several components that mostly accept a request from a topic, do a thing (e.g. collect some data) and publish the result to another topic (or to multiple topics). 

## Models

In this document, the data structures are described using a syntax similar to Python dataclasses. However, in the actual implementation, they are serialized as JSON (this will later be changed to a binary format with pre-defined schemas, probably Avro). The classes implementing the models are [here (Java)](https://github.com/nesfit/domainradar-colext/tree/main/java/common/src/main/java/cz/vut/fit/domainradar/models) and [here (Python)](https://github.com/nesfit/domainradar-colext/blob/main/python/common/models.py).

The serialized values **must** contain all the specified fields. If `| None` is not present, the field **must** have a non-null value.

The base model for all events stored in the *processed_\** topics is `Result`. Every component adds its own specific fields carrying the actual result data to this base structure.

```python
class Result:
    statusCode: int32
    error: str | None
    lastAttempt: int64
```

The status code field contains a code that describes the result (see below).\
The error field *may* contain a human-readable error message if the status code is not 0.\
The last attempt field contains a UNIX timestamp (in milliseconds) of when the operation was *finished*.

### Status codes

| Name                    | Code | Description                                                                                                                                             |
|-------------------------|------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| OK                      | 0    | The operation was successful.                                                                                                                           |
| INVALID_MESSAGE         | 1    | Invalid input message format (deserialization error).                                                                                                   |
| INVALID_DOMAIN_NAME     | 2    | Invalid domain name.                                                                                                                                    |
| INVALID_ADDRESS         | 3    | Invalid IP address.                                                                                                                                     |
| UNSUPPORTED_ADDRESS     | 4    | The IP address is valid but the collector cannot process it.                                                                                            |
| INTERNAL_ERROR          | 5    | A generic error caused inside the collecting system (e.g. invalid state).                                                                               |
| DISABLED                | 6    | The collector is running and has processed the message but it is configured not to do anything.                                                         |
| CANNOT_FETCH            | 10   | Error fetching from remote source.                                                                                                                      |
| TIMEOUT                 | 11   | Timeout while waiting for a response.                                                                                                                   |
| NOT_FOUND               | 12   | Object does not exist.                                                                                                                                  |
| RATE_LIMITED            | 13   | We are rate limited at the remote source.                                                                                                               |
| INVALID_RESPONSE        | 14   | Invalid format of remote source's response.                                                                                                             |
| LOCAL_RATE_LIMIT        | 15   | Local rate limiter in the immediate mode prevented the request.                                                                                         |
| LRL_TIMEOUT             | 16   | Could not pass the local rate limiter in a configured time.                                                                                             |
| OTHER_DNS_ERROR         | 20   | Unexpected DNS error.                                                                                                                                   |
| NO_ENDPOINT             | 30   | RDAP servers are not available for the entity.                                                                                                          |
| WHOIS_NOT_PERFORMED     | 35   | WHOIS was not performed (RDAP was successful).                                                                                                          |
| ICMP_DEST_UNREACHABLE   | 40   | ICMP destination unreachable (generated by the remote host or its inbound gateway to inform the client that the destination is unreachable for some reason). |
| ICMP_TIME_EXCEEDED      | 41   | ICMP time exceeded (a datagram was discarded due to the time to live field reaching zero).                                                              |


## Domain-based collectors

Process requests sent to the zone, DNS, TLS and RDAP-DN collectors are always keyed by a domain name. The keys of the Kafka events should be pure ASCII-encoded strings.

### Zone collector

The zone collector accepts the domain name and finds the SOA record of the zone that contains this domain name. When the SOA is found, finds the addresses of the primary nameserver, secondary nameserver hostnames and their addresses.

When the input is a public suffix (e.g. 'cz', 'co.uk' or 'hakodate.hokkaido.jp'), the resolution is performed so the result is the SOA record of the suffix. Otherwise, the public suffix is skipped (e.g., for 'fit.vut.cz', the query is made for 'vut.cz' and 'fit.vut.cz' but not 'cz').

- Input topic: *to_process_zone*
    - Key: string – DN
    - Value: empty or `ZoneRequest`
- Output topics:
    - *processed_zone*: zone data
        - Key: string – DN
        - Value: `ZoneResult`
    - *to_process_dns*: request for the [DNS collector](#dns--tls-collector)
    - *to_process_RDAP_DN*: request for the [RDAP-DN collector](#rdap-dn-collector)
- Errors:
    - CANNOT_FETCH: Timed out when waiting for a DNS response.
    - NOT_FOUND: No zone found (probably a dead domain name).

```python
class ZoneProcessRequest:
    collectDNS: bool
    collectRDAP: bool
    dnsTypesToCollect: set[str] | None
    dnsTypesToProcessIPsFrom: set[str] | None
```

The request body is optional. If present, it may contain two lists passed to the `DNSProcessRequest` (see below) if the zone is discovered. The two booleans control whether a DNS and an RDAP process requests will be sent to the respective *to_process_\** topics.

```python
class ZoneResult(Result):
    zone: ZoneInfo | None  # null iff statusCode != 0

class ZoneInfo:
    zone: str
    soa: SOARecord
    publicSuffix: str
    primaryNameserverIPs: set[str] | None
    secondaryNameservers: set[str] | None
    secondaryNameserverIPs: set[str] | None

class SOARecord:
    primaryNS: str
    respMailboxDname: str
    serial: str
    refresh: int64
    retry: int64
    expire: int64
    minTTL: int64
```

The primary/secondary NS IPs lists may be null if the corresponding DNS resolutions failed.

### DNS collector

The DNS collector queries the primary nameservers of the input domain name for the requested or pre-configured record types. It also checks the presence of a DNSKEY in the zone. For record types that carry a hostname (CNAME, MX, NS), it also finds the target IP addresses using a common recursive resolver.

- Input topic: *to_process_DNS*: request for the DNS collector
    - Key: string – DN
    - Value: `DNSRequest`
- Output topics:
    - *processed_DNS*: DNS scan result
        - Key: string – DN
        - Value: `DNSResult`
    - *to_process_TLS*: request for the TLS collector
        - Key: string - DN
        - Value: string - the target IP to connect to
    - *to_process_IP*: request for the IP collectors
        - Key: `IPToProcess` (a DN/IP pair)
        - Value: empty
- Errors:
    - INVALID_DOMAIN_NAME: Could not parse the input domain name.
    - OTHER_DNS_ERROR: All issued queries (for all RRtypes) failed. `dnsData` is not null, its `errors` field is set.
    - TIMEOUT: All issued queries (for all RRtypes) timed out.
    - In addition to the common status and error fields, `dnsData` bears information on per-query errors (see below).  

```python
class DNSProcessRequest:
    typesToCollect: set[str] | None
    typesToProcessIPsFrom: set[str] | None
    zoneInfo: ZoneInfo
```

The request body is required. The `zoneInfo` property must contain a valid zone data. 

The `typesToCollect` list is optional and controls which DNS record types will be queried.\
The possible values are: `A, AAAA, CNAME, MX, NS, TXT`, unknown values are ignored.\
If the list is **null or empty**, the value from the collector's configuration will be used.

The `typesToProcessIPsFrom` list is optional and controls the source records types from which IP addresses will be published to *to_process_IP* for further data collection.\
The possible values are: `A, AAAA, CNAME, MX, NS`, unknown values are ignored.\
If the list is **null**, the value from the collector's configuration will be used (unlike in the previous property, non-null but empty value will result in no IPs being published).

```python
class DNSResult(Result):
    dnsData: DNSData | None  # null iff statusCode not in (0, OTHER_DNS_ERROR)
    ips: list[IPFromRecord] | None  # null iff statusCode != 0

class IPFromRecord:
    ip: str
    rrType: str

class DNSData:
    A: set[str] | None
    AAAA: set[str] | None
    CNAME: CNAMERecord | None
    MX: list[MXRecord] | None
    NS: list[NSRecord] | None
    TXT: list[str] | None
    errors: dict[str, str] | None # mappings of "A", "AAAA", ... -> error desc.
    ttlValues: dict[str, int64]   # mappings of "A", "AAAA", ... -> TTL value

class CNAMERecord:
    value: str
    relatedIPs: set[str] | None

class MXRecord:
    value: str
    priority: int32
    relatedIPs: set[str] | None

class NSRecord:
    nameserver: str
    relatedIPs: set[str] | None
```

Each of the `DNSData` properties corresponding to a record type will be non-null iff the record existed in DNS and was fetched sucessfully. If DNS returns NXDOMAIN or no answer, the property will be null.

If another kind of error occurs during a single DNS query, the corresponding property will be null. The `errors` dictionary will be populated with a pair keyed by the record type and a value giving a human-readable error description (e.g., "Timeout"). If all queries fail and at least one of the errors is not a timeout, the response will have the OTHER_DNS_ERROR status code but the data object with the `errors` dictionary will be present. If all queries fail with a timeout, `dnsData` will be null and the overall status code will be TIMEOUT.

|                         | Property not null | Property null                         |
| ----------------------- | ----------------- | ------------------------------------- |
| **Key not in** `errors` | record exists     | record doesn't exist or not requested |
| **Key in** `errors`     | cannot happen     | error processing the record type      |

The `ttlValues` dictionary contains mappings where the key is a successfully fetched record type and the value is the TTL value for the corresponding RRset.

The `relatedIps` properties of `CNAMERecord`, `MXRecord`, `NSRecord` may contain a set of IP addresses acquired by querying a common recursive DNS resolver for the A and AAAA records related to the CNAME value / MX value / nameserver.

### TLS & HTML collector

The TLS & HTML collector opens a TCP connection on an input IP address, port 443, and attempts to perform a TLS handshake (using the input domain name as the SNI value). if successful, it sends an "HTTP GET" message to the URL / and reads the response. If the response is an HTTP message of type "redirect", it follows the destination URL and repeats the process (the maximum number of redirects is configurable). It outputs data on the used protocol, ciphersuite, a list of DER-encoded certificates presented by the server, and the contents of the GET response.

- Input topic: *to_process_TLS*: request for the TLS collector
    - Key: string – DN
    - Value: string - an IP address
- Output topic: *processed_TLS*: TLS handshake and certificate result
    - Key: string – DN
    - Value: `TLSResult`
- Errors:
    - TIMEOUT: Connection or socket I/O timed out.
    - CANNOT_FETCH: Other socket error occurred.

The input value must always be a non-null, non-empty, ASCII-encoded string that contains an IP address. The collector will attempt to establish a TLS connection with this IP on port 443, using the domain name from the key as the SNI (Server Name Indication) value.

```python
class TLSResult(Result):
    tlsData: TLSData | None  # null iff statusCode != 0
    html: str | None  # null if statusCode != 0 or the HTTP request failed

class TLSData:
    fromIP: str
    protocol: str
    cipher: str
    certificates: list[Certificate]

class Certificate:
    dn: str
    derData: bytes
```
The `protocol` field may contain values `"TLSv1", "TLSv1.1", "TLSv1.1", "TLSv1.2", "TLSv1.3"`, according to the protocol determined in the handshake.

The `cipher` property contains an [IANA name (description)](https://www.iana.org/assignments/tls-parameters/tls-parameters.xhtml#tls-parameters-4) of the established ciphersuite.

The `certificates` list contains `Certificate` pairs of distinguished name and raw DER data. It is ordered so that the leaf certificate comes first (at index 0).

### RDAP-DN collector

The RDAP-DN collector looks up domain registration data using the Registration Data Access Protocol. The legacy WHOIS service is used as a fallback in case the TLD does not provide RDAP access or when an error occurs.

- Input topic: *to_process_RDAP_DN*: request for the RDAP-DN collector
    - Key: string – DN
    - Value: empty or `RDAPDomainRequest`
- Output topic: *processed_RDAP_DN*: RDAP/WHOIS query result
    - Key: string – DN
    - Value: `RDAPDomainResult`
- Errors (`statusCode`):
    - RDAP_NOT_AVAILABLE: An RDAP service is not provided for the TLD.
    - NOT_FOUND: The RDAP entity was not found (i.e., the DN does not exist in RDAP).
    - RATE_LIMITED: Too many requests to the target RDAP server.
    - OTHER_EXTERNAL_ERROR: Other error happened (such as non-OK RDAP status code).
- Erros (`whoisStatusCode`, see below):
    - WHOIS_NOT_PERFORMED: RDAP succeeded, no WHOIS query was made.
    - NOT_FOUND: As above.
    - RATE_LIMITED: As above.
    - OTHER_EXTERNAL_ERROR: As above.

```python
class RDAPDomainRequest:
    zone: str | None
```

The request object is not required. If it is provided and it contains a non-null value of the `zone` field, this value will be used as the RDAP (and WHOIS) query target. Otherwise, the source domain name will be used; and, in case of a failure, the DN one level above the public suffix (a "possibly registered domain name") will also be tried.

```python
class RDAPDomainResult(Result):
    rdapTarget: str
    rdapData: dict[str, Any] | None  # null iff statusCode != 0
    entities: dict[str, Any] | None  # null iff statusCode != 0

    whoisStatusCode: int32  # the default value is -1
    whoisError: str | None  # null iff whoisStatusCode != 0
    whoisRaw: str | None  # null iff whoisStatusCode != 0
    whoisParsed: dict[str, Any] | None  # null iff whoisStatusCode != 0
```

The `statusCode` field corresponds to the RDAP query result. If RDAP succeeds, `rdapTarget` contains the domain name that the result actually succeeded for (the source DN, the zone DN or the "registered DN"); `rdapData` contains the deserialized RDAP response JSON. The `entities` field in the RDAP response, if it exists, is removed from the RDAP data and placed in the `entitites` field of the result. It is further processed by following links (a response for a DN may only contain handles to the entities instead of their full details).

A non-zero value of `statusCode` may not signalise a total failure. When (and only if) RDAP fails, WHOIS is tried instead. In this case, `whoisStatusCode` will not be -1, `whoisRaw` may contain the raw WHOIS data, `whoisParsed` may contain a dictionary of parsed WHOIS data (as determined by the [pogzyb/whodap](https://github.com/pogzyb/whodap) library). If `whoisStatusCode` is not 0 nor -1, the `whoisError` field will contain a human-readable error message.

## IP-based collectors

Process requests sent to the RDAP-DN, NERD, RTT and GEO-ASN collectors are always keyed by an `IPToProcess` object, which is essentially a domain name/IP address pair. The IP is transferred in its common string form, both IPv4 and IPv6 addresses are supported.

The request body may be null or an instance of `IPRequest`. It serves as a means of specifying which collectors should run. If the `collectors` list is not null and empty, no collectors will be triggered. If the field or the body are null, all collectors will be triggered.
```python
class IPToProcess:
    dn: str
    ip: str

class IPRequest:
    collectors: set[str] | None
```

The base result model for all IP collector results is `CommonIPResult of TData`.
```python
class CommonIPResult[TData](Result):
    collector: str
    data: TData | None  # null iff statusCode != 0
```

These results carry a string identifier of the collector that created them. The actual data is always stored in field called `data`.

---

- Common input topic for all IP-based collectors: *to_process_IP*
    - Key: `IPToProcess`
    - Value: empty or `IPRequest`
- Common output topic for all IP-based collectors: *collected_IP_data*
    - Key: `IPToProcess`
    - Value: `CommonIPResult of TData` (`TData` is a collector-specific data model)


### RDAP-IP collector

The RDAP-DN collector looks up IP registration data using the Registration Data Access Protocol. Both v4 and v6 are supported.

- Output value: `RDAPIPResult` ~ `CommonIPResult of dict[str, Any]`
- Errors:
    - INVALID_ADDRESS: Could not parse the input string as an IP address.
    - NOT_FOUND: The RDAP entity was not found (i.e., the IP does not exist in RDAP).
    - RATE_LIMITED: Too many requests to the target RDAP server.
    - OTHER_EXTERNAL_ERROR: Other error happened (such as non-OK RDAP status code).

The `data` field of an `RDAPIPResult` is the deserialized JSON response from RDAP. It is taken as-is without any further processing.

### NERD collector

The NERD collectors retrieves the reputation score for the input IP address from CESNET's [NERD](https://nerd.cesnet.cz/) reputation system. 

- Output value: `NERDResult` ~ `CommonIPResult of NERDData`
- Errors:
    - INVALID_FORMAT: Invalid NERD response (content length mismatch).
    - CANNOT_FETCH: NERD responded with a non-OK status code.
    - TIMEOUT: Connection to NERD timed out or waited too long for the answer.

```python
class NERDData:
    reputation: float64  # the default value is 0.0
```

The `data` field of a `NERDResult` is `NERDData`, a container with a single floating-point value representing the reputation. If the address doesn't exist in NERD, the value will be 0. This data model may be extended in the future.

### GeoIP & Autonomous System collector

The GEO-ASN collector looks up information on the geographical location and autonomous system of the input IP address by querying MaxMind's [GeoIP](https://dev.maxmind.com/geoip) databases (locally stored). 

- Output value: `GeoIPResult` ~ `CommonIPResult of GeoIPData`

```python
class GeoIPData:
    continentCode: str | None
    countryCode: str | None
    region: str | None
    regionCode: str | None
    city: str | None
    postalCode: str | None
    latitude: float64 | None
    longitude: float64 | None
    timezone: str | None
    registeredCountryGeoNameId: int64 | None
    representedCountryGeoNameId: int64 | None
    asn: int64 | None
    asnOrg: str | None
    networkAddress: str | None
    prefixLength: int32 | None
```
The `data` field of a `NERDResult` is `NERDData`, a container with values retrieved from the GeoIP (GeoLite2) databases.

### Round-trip time (ping) collector

The RTT collector performs a common ping: it sends a number of ICMP Echo messages to the input IP address, waits for the ICMP Echo Reply answers and outputs basic statistics of the process.

- Output value: `RTTResult` ~ `CommonIPResult of RTTData`
- Errors:
    - ICMP_DESTINATION_UNREACHABLE: The remote host or its inbound gateway indicated that the destination is unreachable for some reason.
    - ICMP_TIME_EXCEEDED: The datagram was discarded due to the time to live field reaching zero.

```python
class RTTData:
    min: float64
    avg: float64
    max: float64
    sent: int32
    received: int32
    jitter: float64
``` 

## Merging the data

The data are being continuously collected and stored in the corresponding *processed_\** topics. Before invoking the feature extractor, they must be merged into a single data object by the Data Merger.

The output topic for the merged data is *all_collected_data*. The final data model is `AllCollectedData`:
```python
class AllCollectedData:
    zone: ZoneInfo
    dnsResult: DNSResult
    tlsResult: TLSResult | None
    rdapDomainResult: RDAPDomainResult | None
    ipResults: dict[str, dict[str, CommonIPResult]] | None
```

Observe that the joining process starts with entries in the *processed_DNS* topic. If zone/SOA resolution fails and the entry is not processed by the DNS collector, the merger is **not** triggered for the domain name and no `FinalResult` is produced. Such entries may be handled by a separate channel picking up failed `ZoneResult`s from *processed_zone*.
