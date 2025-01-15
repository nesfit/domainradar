#!/usr/bin/env bash

source options.sh

########################################################################################

# --- Setup script options ---

USED_PASSWORDS_FILE="./used_passwords"
RANDOM_PASSWORD_LENGTH=32
SECRETS_GENERATION_DIR="./secrets_generation"

# --- Target infrastructure options ---

# Set to 0 to prevent collected data from being stored in PostgreSQL
STORE_RAW_DATA_IN_POSTGRES=0
# The public-facing hostname of the Kafka brokers (% will be replaced by a number)
BROKER_PUBLIC_HOSTNAME="kafka%.example.com"

# NOTE: If you want to use the | character, you need to escape it and include an escaped backslash
#       Example: ["WEBUI_ADMIN_PASSWORD"]="my\\\|password" sets the password to my|password
declare -A config_options=( 
    # -> Collector options <-
    # An API token for CESNET's NERD. Leave empty to disable NERD (i.e. the collector 
    # will run but produce empty responses).
    ["NERD_TOKEN"]=""
    # URL and token for the QRadar RESTful API. Leave the URL empty to disable QRadar
    # (i.e. the collector will run but not consume requests).
    ["QRADAR_URL"]=""
    ["QRADAR_TOKEN"]=""
    
    # -> DomainRadar Web UI <-
    ["WEBUI_ADMIN_USERNAME"]="admin"
    ["WEBUI_ADMIN_PASSWORD"]="please-change-me"
    # The hostname through which the WebUI will be accessed
    # (used as the allowed CORS origin).
    ["WEBUI_PUBLIC_HOSTNAME"]="localhost"
    
    # -> Kafbat UI for Apache Kafka <-
    ["KAFBATUI_ADMIN_USERNAME"]="admin"
    ["KAFBATUI_ADMIN_PASSWORD"]="please-change-me"
    
    # -> Miscellaneous <-
    # IPs of DNS recursive resolvers to use for initial DNS scans.
    # Format as: "\"1.2.3.4\", \"5.6.7.8\"" etc.
    ["DNS_RESOLVERS"]="\"195.113.144.194\", \"195.113.144.233\""
    # A common prefix for the Kafka clients' group ID.
    ["ID_PREFIX"]="domrad"
    # An identifier for the Compose instance.
    ["COMPOSE_BASE_NAME"]="domainradar"
    
    # -> Scaling options (number of component instances to run) <-
    ["COLLECTORS_PY_SCALE"]="5"
    ["COLLECTORS_JAVA_CPC_SCALE"]="1"
    ["EXTRACTOR_SCALE"]="2"
    ["CLASSIFIER_SCALE"]="1"
    # We recommend keeping the scale (number of Docker services) at 1 and increasing
    # the parallelism (number of task slots) to match MAX_PARALLELISM_MERGER
    ["FLINK_TASKMANAGER_SCALE"]="1"
    ["FLINK_PARALLELISM"]="5"

    # -> Kafka partitioning <-
    # These options control the number of partitions set for the Kafka topics used by
    # the pipeline. This effectively controls the maximum number of simultaneously
    # processing instances of the pipeline components. If any of the scaling options
    # above is set to a higher value than the corresponding entry here, the added
    # instances will idle and only take over in case of a failure.
    ["MAX_PARALLELISM_DN_COLLECTORS"]="20"
    ["MAX_PARALLELISM_IP_COLLECTORS"]="20"
    ["MAX_PARALLELISM_MERGER"]="5"
    ["MAX_PARALLELISM_EXTRACTOR"]="10"
    ["MAX_PARALLELISM_CLASSIFIER"]="5"

    # -> Memory limits <-
    ["COLLECTORS_PY_MEM_LIMIT"]="512mb"
    ["COLLECTORS_JAVA_CPC_MEM_LIMIT"]="1024mb"
    ["EXTRACTOR_MEM_LIMIT"]="1024mb"
    ["CLASSIFIER_MEM_LIMIT"]="2gb"
    ["KAFKA_MEM_LIMIT"]="2gb"
    ["POSTGRES_MEM_LIMIT"]="2gb"
    ["FLINK_JOBMANAGER_MEM_PROCESS_SIZE"]="512m"   # This is Flink format, note the missing 'b'
    ["FLINK_TASKMANAGER_MEM_PROCESS_SIZE"]="2048m" # This is Flink format, note the missing 'b'
    ["FLINK_TASKMANAGER_CONTAINER_MEM_LIMIT"]="2560mb"
)

# Passwords for private keys, keystores and database users.
# When left blank, the password will be randomly generated.
# All passwords will be stored in USED_PASSWORDS_FILE.
declare -A passwords=(
    ["PASS_CA"]=""
    ["PASS_TRUSTSTORE"]=""
    # Client certificates and keystores
    ["PASS_KEY_CLASSIFIER_UNIT"]=""
    ["PASS_KEY_CONFIG_MANAGER"]=""
    ["PASS_KEY_COLLECTOR"]=""
    ["PASS_KEY_EXTRACTOR"]=""
    ["PASS_KEY_KAFKA_CONNECT"]=""
    ["PASS_KEY_INITIALIZER"]=""
    ["PASS_KEY_KAFKA_UI"]=""
    ["PASS_KEY_MERGER"]=""
    ["PASS_KEY_LOADER"]=""
    ["PASS_KEY_WEBUI"]=""
    ["PASS_KEY_ADMIN"]=""
    ["PASS_KEY_BROKER_1"]=""
    ["PASS_KEY_BROKER_2"]=""
    ["PASS_KEY_BROKER_3"]=""
    ["PASS_KEY_BROKER_4"]=""
    # Database user passwords
    ["PASS_DB_CONNECT"]=""
    ["PASS_DB_MASTER"]=""
    ["PASS_DB_PREFILTER"]=""
    ["PASS_DB_WEBUI"]=""
    ["PASS_DB_CONTROLLER"]=""
    # Web UI: cookie encryption secret
    ["WEBUI_NUXT_SECRET"]=""  
)

########################################################################################

# --- Setup functions ---

if [[ "$@" =~ "-y" ]]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

stop_on_error() {
    echo "Stopping"
    exit 1
}

ask_yes_no() {
    local prompt="$1"
    local reply

    if $INTERACTIVE; then
        echo "$prompt y"
        return 0
    fi

    while true; do
        read -r -p "$prompt [y/N]: " reply
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no|"" ) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

generate_random_password() {
    local result=""
    # Keep appending until we have at least 32 printable characters
    while [ ${#result} -lt "$RANDOM_PASSWORD_LENGTH" ]; do
        result+=$(head -c 64 /dev/urandom | tr -dc '[:alnum:]')
    done
    # Return exactly 32 printable characters
    echo "${result:0:$RANDOM_PASSWORD_LENGTH}"
}

fill_passwords() {
    if [[ -f "$USED_PASSWORDS_FILE" ]]; then
        if ask_yes_no "A passwords file already exists. Overwrite?"; then
            rm "$USED_PASSWORDS_FILE"
        else
            stop_on_error
        fi
    fi

    for key in "${!passwords[@]}"; do
        if [[ -z ${passwords["$key"]} ]]; then
            passwords["$key"]="$(generate_random_password)"
        fi

        printf "$key\t${passwords[$key]}\n" >> "$USED_PASSWORDS_FILE"
    done

    echo "$USED_PASSWORDS_FILE file written."
}

is_valid_target() {
    local filename="$1"
    local ext="${filename##*.}"
    case "$ext" in
        sh|secret|conf|toml|xml|properties|env|yml|template) return 0 ;;
        *) return 1 ;;
    esac
}

check_properties() {
    has_empty=false

    for key in "${!config_options[@]}"; do
        if [[ -z ${config_options[$key]} ]]; then
            echo "Warning: property $key is empty!" 1>&2
            has_empty=true
        fi
    done

    if $has_empty; then
        if ! ask_yes_no "Empty options found. Continue?"; then
            stop_on_error
        fi
    fi
}

replace() {
    local file="$1"
    local key="$2"
    local value="$3"

    # Replace $$KEY$$ with the corresponding value
    sed -i "s|\\\$\\\$${key}\\\$\\\$|${value}|g" "$file"
}

replace_placeholders() {
    local dir="$1"
    # Recursively process all files under the given directory
    while IFS= read -r -d '' file; do
        # Check if the file is a valid target for variable substitution
        if is_valid_target "$file"; then
            echo "Setting configuration keys in $file"

            for key in "${!config_options[@]}"; do
                replace "$file" "$key" "${config_options[$key]}" 
            done

            for key in "${!passwords[@]}"; do
                replace "$file" "$key" "${passwords[$key]}" 
            done
        fi
    done < <(find "$dir" -type f -print0)
}

configure_sql() {
    if [[ $STORE_RAW_DATA_IN_POSTGRES == "0" ]]; then
        file=$(find "$INFRA_DIR" -type f -name "10_create_domainradar_db.sql" | head -n 1)
        echo "Reconfiguring database init script $file"
        sed -i '/\s*_template_start_/,/\s*_template_end_/ s/v_deserialized_data/NULL/g' "$file"
    fi
}

make_log4j_configs() {
    local dir="$INFRA_DIR/client_properties"
    local template="$dir/log4j2_template.xml"
    local services=(geo_asn nerd tls qradar)

    for service in "${services[@]}"
    do
        target="$dir/log4j2-$service.xml"
        cp "$template" "$target"
        replace "$target" "LOG4J-ID" "collector"
        replace "$target" "LOG4J-KEY" "$service"
        replace "$target" "LOG4J-PASSWORD" "${passwords[PASS_KEY_COLLECTOR]}"
    done
}

# --- Setup process ---

if [[ -d "$INFRA_TEMPLATE_DIR" ]]; then
    if [[ -d "$INFRA_DIR" ]]; then
        # Template backup found and installation exists already
        # => it's only logical to remove the existing installation
        echo "It seems that you have already executed the setup script."
        if ask_yes_no "Remove the existing installation and start anew?"; then
            rm -rf "$INFRA_DIR"
            cp -r "$INFRA_TEMPLATE_DIR" "$INFRA_DIR"
            echo "Removed previous installation."
        else
            stop_on_error
        fi
    else
        # Template backup found but no installation exists
        # => just copy the template
        cp -r "$INFRA_TEMPLATE_DIR" "$INFRA_DIR"
    fi
else
    # No installation done yet => backup the "infra" directory as a template
    cp -r "$INFRA_DIR" "$INFRA_TEMPLATE_DIR"
fi

working_dir="$PWD"

# Create random passwords for those that have not been explicitly set in $passwords
fill_passwords
# Set the internal placeholders according to the target infrastructure options
config_options["BROKER_PUBLIC_HOSTNAME"]="$BROKER_PUBLIC_HOSTNAME"
config_options["KAFKA_PUBLIC_HOSTNAME"]="${BROKER_PUBLIC_HOSTNAME/\%/1}"
# Check if all properties are configured
check_properties
# Replace placeholders in infra
echo "1) Replacing placeholders"
replace_placeholders "$INFRA_DIR"
# Create log4j2 configurations for Java-based collectors
echo "2) Creating Log4J2 configs"
make_log4j_configs
# If STORE_RAW_DATA_IN_POSTGRES is 0, modify the SQL init script in infra
echo "3) Reconfiguring SQL scripts"
configure_sql

echo "4) Generating secrets"
# Backup the secrets generation directory
cp -r "$SECRETS_GENERATION_DIR" "$working_dir/_bck_secrets_gen"
# Replace placeholders in the generate_secrets.sh script
replace_placeholders "$SECRETS_GENERATION_DIR"
# Run the script
cd "$SECRETS_GENERATION_DIR" || exit 1
./generate_secrets_docker.sh
cd "$working_dir"
# Move the newly generated secrets to infra
mv "$SECRETS_GENERATION_DIR/secrets" "$INFRA_DIR/secrets"
# Copy the CA certificate to the loader and webui secerts dirs because they expect them at a fixed location
cp "$INFRA_DIR/secrets/ca/ca-cert" "$INFRA_DIR/secrets/secrets_loader/ca-cert.pem"
cp "$INFRA_DIR/secrets/ca/ca-cert" "$INFRA_DIR/secrets/secrets_webui/ca-cert.pem"
# Restore the backup of the secrets generation directory
rm -rf "$SECRETS_GENERATION_DIR"
mv "$working_dir/_bck_secrets_gen" "$SECRETS_GENERATION_DIR"

# Copy the config_manager host socket script
echo "5) Copying the config_manager host script"
cp "$COLEXT_DIR/python/config_manager/config_manager_daemon.py" "$INFRA_DIR/config-manager-daemon.py"
chmod +x "$INFRA_DIR/config-manager-daemon.py"

# Build container images
echo "6) Building container images"
./build_images.sh
