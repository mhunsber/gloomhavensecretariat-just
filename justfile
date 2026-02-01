set allow-duplicate-variables

# Yes, settings.just overrides settings.default.just: https://github.com/casey/just/issues/2540
import? 'settings.just'
import 'settings.default.just'

DOCKER_IMAGE := "gloomhavensecretariat/ghs-server"
NAME := "ghs-server" # Docker container name
DATADIR := justfile_directory() / 'data' # path to store persistent server data
CLIENTDIR := DATADIR / "gloomhavensecretariat" # path to install secretariat client

KEYSTORE_PASS_FILE := NAME + '.pass'
KEYSTORE_MOUNT_PATH := '/run/ghs.p12'
KEYSTORE_PASS_VAR := 'GHS_KEYSTORE_PASS'
KEYSTORE_CERT_NAME := NAME
LF := "\n"

_default: show_settings
    @just --list \
        --list-heading "{{ BOLD }}Available Commands:{{ NORMAL + LF }}" \
        --list-prefix "> "

show_settings:
    @printf '%s\n' "{{ BOLD }}Current Settings:{{ NORMAL }}"
    @printf '\055 %s: %s\n' \
        "DOCKER_IMAGE" "{{ DOCKER_IMAGE }}" \
        "NAME" "{{ NAME }}" \
        "DATADIR" "{{ DATADIR }}" \
        "CLIENTDIR" "{{ CLIENTDIR }}" \
        "USE_SSL" "{{ USE_SSL }}" \
        "KEYSTORE_MOUNT_PATH" "{{ KEYSTORE_MOUNT_PATH }}" \
        "KEYSTORE_CERT_NAME" "{{ KEYSTORE_CERT_NAME }}" \
        "KEYSTORE_PASS_FILE" "{{ KEYSTORE_PASS_FILE }}" \
        "KEYSTORE_PASS_VAR" "{{ KEYSTORE_PASS_VAR }}" \
        "CERT_FULLCHAIN_PATH" "{{ CERT_FULLCHAIN_PATH }}" \
        "CERT_PRIVATEKEY_PATH" "{{ CERT_PRIVATEKEY_PATH }}" \
        "HTTP_PORT" "{{ HTTP_PORT }}" \
        "HTTPS_PORT" "{{ HTTPS_PORT }}" \
        "SERVE_CLIENT" "{{ SERVE_CLIENT }}" \
        "TAG" "{{ TAG }}"

# list package requirements for this just file
ls-req:
    @printf '%s\n' "{{ BOLD }}Requirements:{{ NORMAL }}"
    @printf '\055 %s\n' \
        jq \
        unzip

#-------------------------------#
#   DOCKER CONTAINER COMMANDS   #
#-------------------------------#

# Enter the ghs container
debug: (_verify_state "created")
    docker exec -it "{{ NAME }}" /bin/sh

# Show ghs container status
status:
    docker inspect "{{ NAME }}" | jq '.[].State.Status'

# Stop ghs
stop:
    docker stop "{{ NAME }}"

# Start ghs
start: (_verify_state "created")
    docker start "{{ NAME }}"

# Remove ghs container
remove: (stop)
    docker rm "{{ NAME }}"

# create and run ghs-server
run port="" data="": (init)
    #!/usr/bin/env bash
    set -u
    docker_create_opts=(--name '{{ NAME }}')

    userport="{{ port }}"
    userdata="{{ data }}"

    data="${userdata:-{{ DATADIR }}}"
    docker_create_opts+=(-v "${data}:/root/.ghs")

    if {{ USE_SSL }}; then
        port="${userport:-{{ HTTPS_PORT }}}"
        p12src="$(mktemp)"
        trap "rm -f $p12src" EXIT SIGINT SIGTERM ERR
        if ! [ -f "$p12src" ]; then
            printf '%s\n' "{{ BOLD + RED }}$p12src does not exist!{{ NORMAL }}"
            exit 1
        fi
        just cert_to_pkcs12 "$p12src"
        keystore_pass="$(cat '{{ KEYSTORE_PASS_FILE }}')"
        rm '{{ KEYSTORE_PASS_FILE }}'
        docker_create_opts+=(-e '{{ KEYSTORE_PASS_VAR }}='"$keystore_pass")
    else
        port="${userport:-{{ HTTP_PORT }}}"
    fi
    docker_create_opts+=(-p "${port}:8080")

    set -e
    docker create "${docker_create_opts[@]}" "{{ DOCKER_IMAGE }}"

    if [ -f "$p12src" ]; then
        docker cp "$p12src" "{{ NAME }}:{{ KEYSTORE_MOUNT_PATH }}"
    fi

    docker start "{{ NAME }}"

#-------------------------------#
#      DATA MANAGEMENT          #
#-------------------------------#

# Update all components. Force will update client even if SERVE_CLIENT is false
update force="false": (update_server) (update_client force "true")

# Get latest ghs-server image
update_server:
    docker pull "{{ DOCKER_IMAGE }}:latest"

# remove the client ghs package
remove_client:
    if [ -d "{{ CLIENTDIR }}" ]; then rm -r "{{ CLIENTDIR }}"; fi

# Get latest client ghs package
update_client force="false" quiet="false":
    #!/usr/bin/env bash
    say() {
        if ! {{ quiet }}; then
            printf '%s\n' "$@"
        fi
    }

    set -eu

    if ! {{ SERVE_CLIENT }} && ! {{ force }}; then       
        say "{{ BOLD + YELLOW }}SERVE_CLIENT is falsey. Use with force=true to force client install{{ NORMAL }}"
        exit 0
    fi

    mkdir -p "{{ CLIENTDIR }}"
    version_file="{{ CLIENTDIR / 'ngsw.json' }}"
    version="0"
    if [ -f "$version_file" ]; then
        version="$(jq -r '.appData.version' "$version_file")"
    fi
    latest_release="https://api.github.com/repos/Lurkars/gloomhavensecretariat/releases/latest"
    jq_filter='.assets[].browser_download_url | select(contains(".zip"))'
    download_url="$(curl -sL "$latest_release" | jq -r "$jq_filter")"
    tag_name="$(echo "$download_url" | cut -d / -f 8)"
    remote_version="${tag_name:1}"
    
    if [ "$version" == "$remote_version" ]; then
        say "client is already at $remote_version"
    else
        say "Updating client to $remote_version..."
        just remove_client

        tmp=$(mktemp)
        trap "rm -f $tmp" EXIT

        set -x
        curl -fL -o "$tmp" "$download_url"
        unzip "$tmp" -d "{{ CLIENTDIR }}"
    fi

# initialize components
init: (_verify_state "removed/uninitialized") (update) (gen_app_props)
    @if [ "{{ SERVE_CLIENT }}" = "false" ]; then just remove_client; fi

# Generate application.properties based on settings
gen_app_props:
    #!/usr/bin/env bash
    set -eu
    file='{{ DATADIR / 'application.properties' }}'
    settings=()
    if {{ USE_SSL }}; then
        keystore_pass_var='{{ KEYSTORE_PASS_VAR }}'
        settings+=(
            "server.ssl.enabled=true"
            "server.ssl.key-store-type=PKCS12"
            "server.ssl.key-store={{ KEYSTORE_MOUNT_PATH }}"
            "server.ssl.key-store-password=\${$keystore_pass_var}"
            "server.ssl.key-alias={{ KEYSTORE_CERT_NAME }}"
        )
    else
        settings+=(
            "server.ssl.enabled=false"
        )
    fi

    tee $file < <(printf '%s\n' "${settings[@]}")

# ------------------------------- #
#       HELPER FUNCTIONS          #
# ------------------------------- #

_verify_state container="created":
    #!/usr/bin/env bash
    set -u
    if ! docker info > /dev/null 2>&1; then
        printf '%s\n' "{{ RED }}Docker does not appear to be running!{{ NORMAL }}"
        exit 1
    fi
    if docker inspect "{{ NAME }}" > /dev/null 2>&1; then
        if [ "{{ container }}" != "created" ]; then
            printf '%s\n' "{{ RED }}'{{ NAME }}' already exists. Run 'just remove' to remove it.{{ NORMAL }}"
            exit 1
        fi
    else
        if [ "{{ container }}" = "created" ]; then
            printf '%s\n' "{{ RED }}'{{ NAME }}' does not exist. Run 'just run' to create it.{{ NORMAL }}"
            exit 1
        fi
    fi

#-------------------------------#
#      SSL SUPPORT              #
#-------------------------------#

# Runs the keytool command in the ghs-server image (don't need java dependency)
keytool *args:
    docker run --rm -it \
        --entrypoint /opt/java/openjdk/bin/keytool \
        "{{ DOCKER_IMAGE }}" \
        {{ args }}

create_keystore_pass length=KEYSTORE_PASSWORD_LENGTH:
    openssl rand -base64 '{{ length }}' >  '{{ KEYSTORE_PASS_FILE }}'

# Exports pem/key to the .p12 file used by ghs-server
cert_to_pkcs12 p12path pass_length=KEYSTORE_PASSWORD_LENGTH: (create_keystore_pass pass_length)
    openssl pkcs12 -export \
        -in '{{ CERT_FULLCHAIN_PATH }}' \
        -inkey '{{ CERT_PRIVATEKEY_PATH }}' \
        -out '{{ p12path }}' \
        -name '{{ KEYSTORE_CERT_NAME }}' \
        -caname 'root' \
        -password 'file:{{ KEYSTORE_PASS_FILE }}'
