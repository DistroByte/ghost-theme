#!/bin/bash

source .env

set -e # exit on error

THEME="edition"
API_VERSION="v3.0"

echo "Deploying $THEME"

# Split the key into ID and SECRET
TMPIFS=$IFS
IFS=':' read ID SECRET <<< "$KEY"
IFS=$TMPIFS

# Prepare header and payload
NOW=$(date +'%s')
FIVE_MINS=$(($NOW + 300))
HEADER="{\"alg\": \"HS256\",\"typ\": \"JWT\", \"kid\": \"$ID\"}"
PAYLOAD="{\"iat\":$NOW,\"exp\":$FIVE_MINS,\"aud\": \"/admin/\"}"

# Helper function for performing base64 URL encoding
base64_url_encode() {
    declare input=${1:-$(</dev/stdin)}
    # Use `tr` to URL encode the output from base64.
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

FILENAME="$(date -I)-${THEME}"

zip -r "dist/$FILENAME.zip" . -x '*git*' '*node_modules*' '*bower_components*'

# Upload theme and extract name and version
curl -s -H "Authorization: Ghost $TOKEN" \
-H "Content-Type: multipart/form-data" \
-H "Accept-Version: $API_VERSION" \
-F "file=@./dist/$FILENAME.zip" \
$SITE_URL/ghost/api/admin/themes/upload/ | jq '.'

# Activate theme
curl -s -H "Authorization: Ghost $TOKEN" \
-H "Accept-Version: $API_VERSION" \
-X PUT "$SITE_URL/ghost/api/admin/themes/$FILENAME/activate/" | jq -r '.themes[] | .name, .package.version'
