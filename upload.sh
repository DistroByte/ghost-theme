#!/bin/bash

source .env

set -e # exit on error

THEME="edition"
API_VERSION="v5.0"

if [[ -z "$KEY" || -z "$SITE_URL" ]]; then
    echo "Error: KEY and SITE_URL environment variables must be set."
    exit 1
fi

# Clean KEY of null bytes and whitespace
CLEAN_KEY=$(echo -n "$KEY" | tr -d '\000' | tr -d '\r\n' | xargs)

# Split the key into ID and SECRET
TMPIFS=$IFS
IFS=':' read ID SECRET <<< "$CLEAN_KEY"
IFS=$TMPIFS

if [[ -z "$ID" || -z "$SECRET" ]]; then
    echo "Error: KEY must be in the format <id>:<secret>"
    exit 1
fi

# Check if SECRET is 64 hex chars
if ! [[ $SECRET =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "Error: SECRET must be a 64-character hex string."
    exit 1
fi

# Prepare header and payload
NOW=$(date +'%s')
FIVE_MINS=$(($NOW + 300))
HEADER="{\"alg\": \"HS256\",\"typ\": \"JWT\", \"kid\": \"$ID\"}"
PAYLOAD="{\"iat\":$NOW,\"exp\":$FIVE_MINS,\"aud\": \"/admin/\"}"

# Helper function for performing base64 URL encoding
base64_url_encode() {
    declare input=${1:-$(</dev/stdin)}
    printf '%s' "${input}" | basenc --base64url | tr -d '=' | tr '/+' '_-' | tr -d '\n'
}

# Prepare the token body
header_base64=$(base64_url_encode "${HEADER}")
payload_base64=$(base64_url_encode "${PAYLOAD}")

header_payload="${header_base64}.${payload_base64}"

# Create the signature
signature=$(printf '%s' "${header_payload}" | openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:$SECRET | base64_url_encode)

# Concat payload and signature into a valid JWT token
TOKEN="${header_payload}.${signature}"

echo "Deploying $THEME"

curl --write-out 'HTTP %{http_code}\n' -s -o /dev/null -H "Authorization: Ghost $TOKEN" \
-H "Content-Type: multipart/form-data" \
-H "Accept-Version: $API_VERSION" \
-F "file=@./dist/$THEME.zip" \
$SITE_URL/ghost/api/admin/themes/upload/

echo "Theme uploaded successfully."

echo "Activating theme..."
curl -s -H "Authorization: Ghost $TOKEN" \
-H "Accept-Version: $API_VERSION" \
-X PUT "$SITE_URL/ghost/api/admin/themes/$THEME/activate/" | jq -r '.themes[] | .name, .package.version'

if [[ $? -ne 0 ]]; then
    echo "Error activating theme."
    exit 1
fi

echo "Theme activated successfully."