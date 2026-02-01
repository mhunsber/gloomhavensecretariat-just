TAG := 'latest' # docker tag to use for ghs-server
SERVE_CLIENT := 'false' # whether or not to include the gloomhaven secretariat client

HTTP_PORT := '8000' # Port to use when running without a certificate
HTTPS_PORT := '8443' # Port to use when running with a certificate

# Define settings for SSL
USE_SSL := 'false'
KEYSTORE_PASSWORD_LENGTH := '16'
CERT_FULLCHAIN_PATH := 'mycerts/fullchain.cer'
CERT_PRIVATEKEY_PATH := 'mycerts/private.key'
