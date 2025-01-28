# DomainRadar

DomainRadar is an ML-based system for the identification of malicious domain names using information collected from external sources.

This repository contains pieces of [documentation](./docs/) and resources for quickly setting up a complete DomainRadar demonstration environment. The actual system components are located in sister repositories:

- [domainradar-input](https://github.com/nesfit/domainradar-input) contains the Loader & Pre-filter component,
- [domainradar-colext](https://github.com/nesfit/domainradar-colext) contains the distributed data processing pipeline components for collection and feature extractor,
- [domainradar-clf](https://github.com/nesfit/domainradar-clf) contains the classifiers,
- [domainradar-ui](https://github.com/nesfit/domainradar-ui) contains the user web interface,
- [domainradar-infra](https://github.com/nesfit/domainradar-infra) contains a _template_ for a Docker Compose setup, including service configurations and database initialization scripts.

## System requirements

The _minimum_ requirements for the host machine are:
- 16 GB of RAM (available to DomainRadar)
- 64 GB of storage
- 4 CPU cores 

We recommend to run the system with at least 24 GB of RAM and 8 CPU cores.

The demonstration environment was tested using:
- Debian 12.2.0
- Docker Engine 27.0.3
- Docker Compose 2.29.7

Any reasonably recent version of Docker (and Compose) should work. The setup was not tested with other container platforms, though it seems to work on rootful Podman _with SELinux disabled_.

## Setting up

This repo contains the following scripts you may want to use:

- [options.sh](./options.sh) defines the paths and target branches for the repos mentioned above. It is sourced by the other scripts and does nothing on its own.
- [pull.sh](./pull.sh) clones the repos.
- [clean.sh](./clean.sh) removes the source code and/or the built container images.

At the top of the main [setup.sh](./setup.sh) script, you'll find a number of **configuration options** (with comments) for the target environment. You can also specify various **internal passwords and secrets** (such as passwords for the database users), though when you leave those blank, they will be generated for you.

The script expects all the DomainRadar repos to be cloned at paths set in [options.sh](options.sh) (which can be done using [pull.sh](./pull.sh)).

> [!IMPORTANT]
> Don't forget to pull the other repositories **and** to set the configuration options before running the setup script.

The script:

- Creates a backup of the `INFRA_DIR` directory with the template (allowing the script to be re-executed later, e.g., to set up an environment with a different configuration).  
- Generates passwords and secrets (if not specified explicitly in the setup script).
- Verifies that all configuration items are filled in.  
- Populates the configuration template files in the `INFRA_DIR` directory.  
- Creates a local certificate authority and a set of certificates used to authenticate clients when communicating with Apache Kafka servers.  
- Builds container images for all the services.

> [!NOTE]
> The setup script is interactive. If it detects that it has been executed before, it asks the user whether to overwrite the previous content. You can use the `-y` to skip this.

After completing the script, you can navigate to your `INFRA_DIR` and initialize the Apache Kafka server and DomainRadar using the following commands:

```bash
docker compose up -d kafka1 postgres
docker compose up --build initializer
docker compose up -d
```

You can verify the successful startup of the DomainRadar tool by accessing the web interface at [http://localhost:31003/](http://localhost:31003/) or the Kafka server management interface at [http://localhost:31000/](http://localhost:31000/) (default settings). The login credentials for both interfaces are configuration items set by the setup script.

Later on, you can start and stop DomainRadar using the following commands:

```bash
docker compose up -d  # Start
docker compose down   # Stop
```

> [!TIP]
> See the README in [domainradar-infra](https://github.com/nesfit/domainradar-infra/) for more information on the infrastructure files layout, the initialization script, the services and the available advanced configuration options.
