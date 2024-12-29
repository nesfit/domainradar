#!/usr/bin/env bash

# --- Setup script options ---
GENERATED_PASSWORDS_FILE="./generated_passwords"
RANDOM_PASSWORD_LENGTH=32

source options.sh
SECRETS_GENERATION_DIR="./secrets_generation"

# --- Target infrastructure options ---

# Set to 0 to prevent collected data from being stored in PostgreSQL
STORE_RAW_DATA_IN_POSTGRES=0
# The public-facing hostname of the Kafka brokers (% will be replaced by a number)
BROKER_PUBLIC_HOSTNAME="kafka%.example.com"

declare -A config_options=( 
    # Collector options
    ["NERD_TOKEN"]="123456789"
    # DomainRadar Web UI
    ["WEBUI_ADMIN_USERNAME"]="admin"
    ["WEBUI_ADMIN_PASSWORD"]="please-change-me"
    ["WEBUI_PUBLIC_HOSTNAME"]="localhost"
    # Kafbat UI for Apache Kafka
    ["KAFBATUI_ADMIN_USERNAME"]="admin"
    ["KAFBATUI_ADMIN_PASSWORD"]="please-change-me"
    # Misc
    ["DNS_RESOLVERS"]="\"195.113.144.194\", \"195.113.144.233\""
    ["ID_PREFIX"]="domrad"
    ["COMPOSE_BASE_NAME"]="domainradar"
    # Compose scaling
    ["COLLECTORS_PY_SCALE"]="5"
    ["COLLECTORS_JAVA_CPC_SCALE"]="1"
    ["EXTRACTOR_SCALE"]="2"
    ["CLASSIFIER_SCALE"]="1"
    ["FLINK_TASKMANAGER_SCALE"]="1"
)

# Passwords for private keys, keystores and database users
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

# --- Setup functions ---

if [[ "$@" =~ "-y" ]]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

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
    if [[ -f "$GENERATED_PASSWORDS_FILE" ]]; then
        if ask_yes_no "A passwords file already exists. Overwrite?"; then
            rm "$GENERATED_PASSWORDS_FILE"
        else
            echo "Terminating"
            exit 1
        fi
    fi

    for key in "${!passwords[@]}"; do
        if [[ -z ${passwords["$key"]} ]]; then
            passwords["$key"]="$(generate_random_password)"
        fi

        printf "$key\t${passwords[$key]}\n" >> "$GENERATED_PASSWORDS_FILE"
    done
}

is_valid_target() {
    local filename="$1"
    local ext="${filename##*.}"
    case "$ext" in
        sh|secret|conf|toml|xml|properties|env|yml) return 0 ;;
        *) return 1 ;;
    esac
}

check_properties() {
    for key in "${!config_options[@]}"; do
        if [[ -z ${config_options[$key]} ]]; then
            echo "Warning: property $key is empty!" 1>&2
        fi
    done
}

replace() {
    local file="$1"
    local key="$2"
    local value="$3"

    # Replace $$KEY$$ with the corresponding value
    sed -i "s/\\\$\\\$${key}\\\$\\\$/${value}/g" "$file"
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
    local services=(geo_asn nerd tls)

    for service in "${services[@]}"
    do
        target="$dir/log4j2-$service.xml"
        cp "$template" "$target"
        replace "$target" "LOG4J-ID" "collector"
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
        else
            exit 1
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
replace_placeholders "$INFRA_DIR"
# Create log4j2 configurations for Java-based collectors
make_log4j_configs
# If STORE_RAW_DATA_IN_POSTGRES is 0, modify the SQL init script in infra
configure_sql

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
# Restore the backup of the secrets generation directory
rm -rf "$SECRETS_GENERATION_DIR"
mv "$working_dir/_bck_secrets_gen" "$SECRETS_GENERATION_DIR"

# Build container images
./build_images.sh
