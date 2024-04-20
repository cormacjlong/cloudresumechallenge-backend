#!/bin/bash
set -e

eval "$(jq -r '@sh "AZURE_CLIENT_ID=\(.client_id) AZURE_TENANT_ID=\(.tenant_id) AZURE_SUBSCRIPTION_ID=\(.subscription_id)"')"

if [[ "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" == "" ]] || [[ "$ACTIONS_ID_TOKEN_REQUEST_URL" == "" ]]
then
  # This is ok, we're probably running locally
  jq -n '{}'
  exit 0
fi

# get JWT from GitHub's OIDC provider
# see https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#updating-your-actions-for-oidc
jwt_token=$(
  curl "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" \
    -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    --silent \
  | jq -r ".value"
)

# perform OIDC token exchange
az login \
  --service-principal -u $AZURE_CLIENT_ID \
  --tenant $AZURE_TENANT_ID \
  --federated-token $jwt_token \
  -o none

az account set \
  --subscription $AZURE_SUBSCRIPTION_ID \
  -o none

jq -n '{}'

# https://github.com/Azure/login/issues/180#issuecomment-1911115593