#!/bin/bash

# Usage: ./generate_new_client_secret.sh <client alias> <client password>
# Generates a self-signed CA, then generates SSL keys and signs certificates for Kafka brokers and clients.
# Requires OpenSSL and Java JRE.

CLIENT_CERT_VALIDITY_DAYS=365

SECRETS_DIR="secrets"
CA_KEYSTORE="ca"

cd "$SECRETS_DIR" || exit 1

# Generate client keypairs and certificates
CLIENT_ID="$1"
CLIENT_PASSWORD="$2"

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_PASSWORD" ]; then
    echo "Usage: ./generate_new_client_secret.sh <client name> <client password>"
    exit 1
fi

echo "Creating $CLIENT_ID keystore and certificate..."

keytool -keystore "$CLIENT_ID.keystore.jks" -alias "$CLIENT_ID" -validity $CLIENT_CERT_VALIDITY_DAYS -genkey \
    -keyalg RSA -storepass "$CLIENT_PASSWORD" -keypass "$CLIENT_PASSWORD" \
    -dname "CN=$CLIENT_ID, OU=KafkaClients, O=DomainRadar, L=Brno, C=CZ"

keytool -keystore "$CLIENT_ID.keystore.jks" -alias "$CLIENT_ID" -certreq -file "$CLIENT_ID.csr" -storepass "$CLIENT_PASSWORD" -keypass "$CLIENT_PASSWORD"

cd "$CA_KEYSTORE" || exit 1
openssl ca -batch -config ../../openssl-ca.cnf -policy signing_policy -extensions signing_req \
    -days "$CLIENT_CERT_VALIDITY_DAYS" -out "../$CLIENT_ID-cert.pem" -infiles "../$CLIENT_ID.csr"
cd .. || exit

# Import the CA certificate
keytool -keystore "$CLIENT_ID.keystore.jks" -alias CARoot -import -file "$CA_KEYSTORE/ca-cert" -storepass "$CLIENT_PASSWORD" -noprompt
# Import the signed clientcertificate
keytool -keystore "$CLIENT_ID.keystore.jks" -alias "$CLIENT_ID" -import -file "$CLIENT_ID-cert.pem" -storepass "$CLIENT_PASSWORD" -noprompt
# Export to PKCS12 and then to PEM
keytool -importkeystore -srckeystore "$CLIENT_ID.keystore.jks" -srcstorepass "$CLIENT_PASSWORD" -destkeystore "$CLIENT_ID.keystore.p12" -deststoretype PKCS12 -deststorepass "$CLIENT_PASSWORD"
openssl pkcs12 -in "$CLIENT_ID.keystore.p12" -nocerts -out "$CLIENT_ID-priv-key.pem" -passin "pass:$CLIENT_PASSWORD" -passout "pass:$CLIENT_PASSWORD"
rm "$CLIENT_ID.keystore.p12"
rm ./*.csr

mkdir -p "secrets_$CLIENT_ID"
echo "$CLIENT_PASSWORD" > "secrets_$name/key-password.txt"
mv "$CLIENT_ID"* "secrets_$CLIENT_ID/"

echo "Generated client private key and certificate for $CLIENT_ID."
