#!/bin/bash

# name of the environment
export ENV_NAME=example-gke

# relative or absolute path of your envs directory, effectively where the directory
# containing this script sits relative to the helmfile dir.
export ENV_DIR="./envs/${ENV_NAME}/"


## General
# cloud provider (currently only supports gcp)
export CLOUD_PROVIDER=gcp

## Google
export GOOGLE_PROJECT_ID=
# the location of a GCP auth JSON file for a service-account
# needs perms for a bunch of stuff.
export GOOGLE_APPLICATION_CREDENTIALS_FILE="$ENV_DIR/key.json"
export GOOGLE_APPLICATION_CREDENTIALS_SECRET=$(cat ${GOOGLE_APPLICATION_CREDENTIALS_FILE} | base64 -w0)

## external-dns
# pre-created secret containing your GCP creds. gcp-lb-tags chart creates a secret
# we can use here.
export EXTERNAL_DNS_SECRET="google-credentials"
# DNS domain for external-dns controller to manage should be a google dns
# managed zone
export EXTERNAL_DNS_DOMAIN=

## cert-manager
export CERT_MANAGER_EMAIL=

## Eirini
export EIRINI_DOMAIN=app.cf.${EXTERNAL_DNS_DOMAIN}
export EIRINI_BITS_SECRET=
export EIRINI_ADMIN_PASSWORD=
export EIRINI_ADMIN_CLIENT_SECRET=

## Grafana
export GRAFANA_ADMIN_PASSWORD=