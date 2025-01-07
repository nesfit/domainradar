# Runtime configuration exchange

All the components in the system use various configuration properties. This document describes how configuration may be distributed among them at runtime.

Kafka is used as the data bus for storing and distributing the configurations. The `configuration_change_requests` topic is used to update the configuration of any component. All events published to this topic have:
- key: the target component ID,
- value: the entire configuration object serialized as JSON.

When an event is consumed from `configuration_change_requests`, the component checks if its ID matches the key and if so, validates the input configuration object. If it's valid, the current configuration is **replaced** with this object. After a request is processed (both valid and invalid), a response event is published.

The `configuration_states` topics is used to provide responses to configuration change requests. All events published to this topic have:
- key: the affected component ID,
- value: a `ConfigurationChangeResult` object (see below) serialized as JSON. 

When any component starts, it **must** load its runtime configuration by reading the `configuration_states` topic from the start (offset 0) and applying the configuration from the `currentConfig` field of the *last* event with a key corresponding to the component's ID. If no such event is found, the component **must** use apply its predefined defaults and **publish** a change result message, as if the configuration was just changed.

This implies that Kafka connection parameters must be configured statically. The components **should** ensure that the Kafka connection parameters cannot be changed using the runtime configuration exchange.

Note: The request topic is regularly cleaned, so the messages are considered transient. The reponse topic is compacted, so only after some time, only the most recent configuration event will be stored. For this reason, even unsuccessful results must carry a snapshot of the last valid configuration.

## Configuration change results

The reponse model is defined as:
```python
class ConfigurationChangeResult:
    success: bool
    errors:  list[ConfigurationValidationError] | None
    message: str | None
    currentConfig: dict[str, json]

class ConfigurationValidationError:
    propertyPath: str
    errorCode:    int
    error:        str | None
    soft:         bool
```

- `currentConfig` **always** contains a complete snapshot of the currently used runtime configuration (i.e., the last successfully applied one).
- `success` is true if (and only if) the configuration was successfully applied.
- `errors` may contain a list of `ConfigurationValidationError` values that describe the individual errors (or warnings) per property. Their `errorCode` field contains one of the values from the table below.
- `message` may contain an arbitrary human-readable message describing the result.

There might be multiple errors for a single property. A validation error may be *soft*, i.e., it did not prevent the configuration from being applied but may cause issues. In this case, the validation error is interpreted as a warning.

### Error codes

| Code | Name              | Description |
| ---- | ----------------- | ----------- |
| 1    | OTHER             | Unspecified error. |
| 2    | INVALID\_MESSAGE  | Invalid input message format (configuration model deserialization error). |
| 3    | INVALID\_PROPERTY | No such configuration property exists. |
| 4    | INVALID\_TYPE     | Invalid data type of the provided value. |
| 5    | OUT\_OF\_RANGE    | The provided value is out of the allowed range. |
| 6    | READ\_ONLY        | The property cannot be changed dynamically. |
| 7    | MISSING           | The property must be explicitly defined. |

## Component IDs

The available component IDs are:
- loader
- collector-zone
- collector-dns
- collector-tls
- collector-nerd
- collector-geo-asn
- collector-rdap-dn
- collector-rdap-ip
- collector-rtt
- fl-taskmanager (corresponds to the Data Merger configuration)
- extractor
- classifier

## Configuration format (loader)

The configuration exchange JSON for the loader looks like this:
```json
{
    "sources": [
        {
            "type": "ELKSource",
            "args": [],
            "kwargs": {
                "elk_url": "[ELK URL]",
            }
        }
    ],
    "filters": [
        {
            "type": "FileBlockListFilter",
            "args": [],
            "kwargs": {
                "filter_result_action": "FilterAction.STORE",
                "filename": "block.list"
            }
        },
        {
            "type": "FileBlockListFilter",
            "args": [],
            "kwargs": {
                "filter_result_action": "FilterAction.DROP",
                "filename": "block2.list"
            }
        }
    ],
    "outputs": [
        {
            "type": "StdOutput",
            "args": [],
            "kwargs": {},
        },
        {
            "type": "PostgresOutput",
            "args": [],
            "kwargs": {
                "host": "[PostgreSQL Host]",
                "port": 31010,
                "username": "prefilter",
                "password": "[PostgreSQL Password]",
                "database": "domainradar",
            }
        }
    ]
}
```

## Configuration format (Java-based data pipeline components)

For the pipeline components implemented in Java, the configuration exchange JSON will be transformed into the Java Properties file accepted by the components. No type checks are performed!

The configuration exchange object has two top-level properties. Its `collector` section maps to the collector-specific configuration keys, as defined in the file linked above. Omit the `collectors.` prefix from the key. \
The `system` section can be used to directly manipulate the options for the Kafka Consumers/Producers. 


The configuration exchange JSON has this format:
```json
{
    "collector": {
        "any property prefixed with collector without the prefix": "value, e.g.",
        "parallel.consumer.max.concurrency": 32,
        "nerd.token": "xyz"
    },
    "system": {
        "any non-collector-specific property": "value, e.g.",
        "producer.compression.type": "zstd",
    }
}
```

For example, the JSON:
```json
{
    "collector": {
        "parallel.consumer.max.concurrency": 32,
        "nerd.token": "xyz",
        "nerd.timeout": 5
    },
    "system": {
        "producer.compression.type": "zstd",
    }
}
```
will be mapped to:
```properties
collectors.parallel.consumer.max.concurrency=32
collectors.nerd.token=xyz
collectors.nerd.timeout=5
producer.compression.type=zstd
```

## Configuration format (Python-based data pipeline components)

For the pipeline components implemented in Python, the configuration exchange JSON will be transformed into the TOML configuration file accepted by the components. Generally, the collector-specific options will be properties of a top-level object named by the collector; its embedded dictionary `faust` passes options directly to the underlying framework.

The configuration exchange JSON will be mapped 1:1 to the target TOML (using [tomli-w](https://pypi.org/project/tomli-w)). However, the `connection` section and the `app_id` keys will be omitted! 

For example:
```json
{
    "rdap_ip": {
        "http_timeout_sec": 5,
        "app_id": "this-wont-be-used",
        "faust": {
            "producer_compression_type": "zstd"
        }
    }
}
```
will be mapped to:
```toml
[rdap_ip]
http_timeout_sec = 5

[rdap_ip.faust]
producer_compression_type = "zstd"
```
