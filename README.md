# Gloomhaven Secretariat Server — just/docker runner

A collection of `just` recipes to run and manage a [Gloomhaven Secretariat Server](https://github.com/Lurkars/ghs-server) using Docker. Provides recipes for installing the client, upgrading components, and configuring the server to run using TLS.

_note_: This is essentially a personal project, so I've made some choices that may be unique to my system.

## Prerequisites

- `just` — command runner: https://just.systems/
- `docker` — container runtime: https://docs.docker.com/get-started/

## Getting started

- Create a `settings.just` to override the defaults in `settings.default.just`.

- An example file for enabling TLS using a key generated with acme.sh:

```just
CERT_FULLCHAIN_PATH := home_directory() / '.acme.sh/mydomain_ecc/fullchain.cer'
CERT_PRIVATEKEY_PATH := home_directory() / '.acme.sh/mydomain_ecc/mydomain.key'
USE_SSL := 'true'
```

- Run the server with `just run`

- List other available commands with `just`
