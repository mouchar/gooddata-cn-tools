#!/usr/bin/env bash
# (C) 2020-2024 GoodData Corporation
#
# Create K3D cluster with Pulsar and GoodData.CN Helm charts deployed.
# SW Requirements:
# * kubectl 1.24+
# * k3d 5.4.x+
# * helm 3.x
# * dockerd 20.x+
# * jq
# * envsubst (part of gettext package, also available in Homebrew)
# * (optional but recommended) crane (https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md)
# Environment requirements:
# * GDCN_LICENSE contaning GoodData.CN license key
#
# Steps to start local k3d cluster:
#   1. (Optional) prepare GD.CN deployment customization - check section "Customizing GD.CN deployment values"
#   2. run './k3d.sh -c' to deploy whole cluster (can take ~ 10min, rerun without "-c" if it times out)
#   3. (Optional) Imort generated self-signed CA certificate to browser and operating system.
#   3. Create Organization with localhost hostname, create user in dex and metadata. Follow GoodData docs.
#   4. go to https://localhost, and use credentials for user created in step 3.
##
# Customizing GD.CN deployment values:
#  Values customizations is available through option '-f FILE' of './k3d-deploy.sh'. Below is an example how to set
#  offline feature flag ENABLE_PDM_REMOVAL_DEPRECATION_PHASE:
#    1. create file /tmp/custom-values.yaml with content:
#    commonEnv:
#      - name: GDC_FEATURES_VALUES_ENABLE_PDM_REMOVAL_DEPRECATION_PHASE
#        value: "true"
#    2. In step (3) of "Steps to start local k3d cluster" run './k3d-deploy.sh -c -b -v /tmp/custom-values.yaml'
#

set -e
DOCKERHUB_NAMESPACE="gooddata"
PULSAR_VERSION="3.1.2"
PULSAR_CHART_VERSION="3.1.0"
GDCN_VERSION="3.13.0"
CLUSTER_NAME="default"
# set to empty string if you want port 80
LBPORT=""
# set to empty string if you want port 443
LBSSLPORT=""
export K3D_HTTP_PORT="${LBPORT:-80}"
export K3D_HTTPS_PORT="${LBSSLPORT:-443}"

DOCKET_REGISTRY_HOST=localhost
export DOCKER_REGISTRY_PORT=5000
# Hint: if you want to use your own registry, you can set DOCKET_REGISTRY and REPOSITORY_PREFIX to some
# other compatible registry. Images will be copied to that registry.
gOCKER_REGISTRY="$DOCKET_REGISTRY_HOST:$DOCKER_REGISTRY_PORT"
REPOSITORY_PREFIX="k3d-registry:$DOCKER_REGISTRY_PORT"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

pushd "$SCRIPT_DIR"
K3D_CONFIG_FILE="k3d-config.yaml"
# Fancy colors
C_RED='\033[0;31m'
C_RESET='\033[0m'

# List of images to be copied from docker hub to local docker registry
declare -A IMAGES=(
  ["afm-exec-api"]="$DOCKERHUB_NAMESPACE/afm-exec-api"
  ["api-gateway"]="$DOCKERHUB_NAMESPACE/api-gateway"
  ["auth-service"]="$DOCKERHUB_NAMESPACE/auth-service"
  ["automation"]="$DOCKERHUB_NAMESPACE/automation"
  ["calcique"]="$DOCKERHUB_NAMESPACE/calcique"
  ["export-controller"]="$DOCKERHUB_NAMESPACE/export-controller"
  ["metadata-api"]="$DOCKERHUB_NAMESPACE/metadata-api"
  ["result-cache"]="$DOCKERHUB_NAMESPACE/result-cache"
  ["scan-model"]="$DOCKERHUB_NAMESPACE/scan-model"
  ["sql-executor"]="$DOCKERHUB_NAMESPACE/sql-executor"
  ["tabular-exporter"]="$DOCKERHUB_NAMESPACE/tabular-exporter"
  ["apidocs"]="$DOCKERHUB_NAMESPACE/apidocs"
  ["dex"]="$DOCKERHUB_NAMESPACE/dex"
  ["organization-controller"]="$DOCKERHUB_NAMESPACE/organization-controller"
  ["tools"]="$DOCKERHUB_NAMESPACE/tools"
  # amd64/arm64
  ["analytical-designer"]="$DOCKERHUB_NAMESPACE/analytical-designer"
  # amd64/arm64
  ["dashboards"]="$DOCKERHUB_NAMESPACE/dashboards"
  # amd64/arm64
  ["home-ui"]="$DOCKERHUB_NAMESPACE/home-ui"
  # amd64/arm64
  ["ldm-modeler"]="$DOCKERHUB_NAMESPACE/ldm-modeler"
  # amd64/arm64
  ["measure-editor"]="$DOCKERHUB_NAMESPACE/measure-editor"
  # amd64/arm64
  ["web-components"]="$DOCKERHUB_NAMESPACE/web-components"
  # amd64/arm64
  ["quiver"]="$DOCKERHUB_NAMESPACE/quiver"
  # amd64 only
  ["visual-exporter-chromium"]="$DOCKERHUB_NAMESPACE/visual-exporter-chromium"
  ["visual-exporter-proxy"]="$DOCKERHUB_NAMESPACE/visual-exporter-proxy"
  ["visual-exporter-service"]="$DOCKERHUB_NAMESPACE/visual-exporter-service"
  ["pdf-stapler-service"]="$DOCKERHUB_NAMESPACE/pdf-stapler-service"
)

# Play safe and cover all imaginable options
case $(arch) in
  x86_64 | amd64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *)
    echo -e"${C_RED}⛔ Unsupported architecture: $(arch)${C_RESET}"
    exit 1
    ;;
esac

usage() {
  cat >/dev/stderr <<EOT
    Usage: $0 [options]
    Options are:
      -c - create cluster
      -v VERSION - use this version of gooddata-cn helm chart
      -f FILE - full path to a yaml with GD.CN helm values

EOT
  exit 1
}

docker_cp() {
  from=$1
  to=$2
  echo "Copying $from to $to"
  if [ "$HAS_CRANE" == "1" ]; then
    # copy only platform specific image to local registry
    crane cp --platform linux/$ARCH "$from" "$to"
  else
    docker pull -q "$from"
    docker tag "$from" "$to"
    docker push -q "$to"
  fi
}

[ -z "$GDCN_LICENSE" ] && {
  echo "License key must be stored in GDCN_LICENSE environment variable."
  exit 1
}

v() {
  echo "Running: $*"
  "$@"
}

CREATE_CLUSTER=""
VALUES_FILE=""

while getopts ":cv:f:" o; do
  case "${o}" in
  c)
    CREATE_CLUSTER=yes
    ;;
  f)
    VALUES_FILE="$OPTARG"
    ;;
  v)
    GDCN_VERSION="$OPTARG"
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND - 1))

echo "Checking for missing tools"
helm version
kubectl version --client
docker ps -q >/dev/null
command -v envsubst >/dev/null || {
  echo "⛔ Can not find 'envsubst' command."
  exit 1
}
command -v crane >/dev/null 2>&1 && {
  echo "🎉 Found crane, will use it to copy images to local registry"
  HAS_CRANE=1
}

echo "🔎 Checking GoodData CN version"
# If this command fails, provided version does not exist in Docker Hub
docker manifest inspect $DOCKERHUB_NAMESPACE/dex:$GDCN_VERSION >/dev/null || {
  echo "⛔ Can not access images in Docker Hub. Make sure $GDCN_VERSION is valid."
  exit 1
}

# This is needed to make kubedns working in pods running on the same host
# where kubedns pod is running; valid for Linux
if [ "$(uname -s)" == "Linux" ]; then
  echo "🔎 Checking bridge netfilter policy"
  if ! grep -q 1 /proc/sys/net/bridge/bridge-nf-call-iptables; then
    echo "  Enabling bridge-nf-call-iptables"
    echo '1' | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables
  fi
  # This is needed for klipper in order to configure NAT table
  echo "🔎 Checking if iptables module is present"
  if [ ! -d /sys/module/ip_tables ]; then
    echo "Loading iptables to kernel"
    insmod ip_tables || exit 1
  fi
fi

# Create cluster
if [ "$CREATE_CLUSTER" ]; then
  k3d cluster delete $CLUSTER_NAME || :
  k3d cluster create -c "$K3D_CONFIG_FILE"
fi

# Use ext-image files to get correct image tag. Note this tag refers to the repository
# where the image was built.
echo "Copying images"
for app in "${!IMAGES[@]}"; do
  docker_cp "${IMAGES[$app]}:$GDCN_VERSION" "$DOCKER_REGISTRY/${app}:$GDCN_VERSION" &
done

wait # wait for copying to complete

if [ "$CREATE_CLUSTER" ]; then
  k3d kubeconfig merge default -d
  kubectl config use-context k3d-$CLUSTER_NAME
  kubectl create ns pulsar
  kubectl create ns gooddata
fi

# Preload pulsar to local registry
# The reason is that it is a huge image and DockerHub token expires before the image
# is pulled by containerd. Furthermore, is is pulled 3-4 times in parallel.
docker_cp apachepulsar/pulsar:$PULSAR_VERSION $DOCKER_REGISTRY/apachepulsar/pulsar:$PULSAR_VERSION

kubectl config use-context k3d-$CLUSTER_NAME
kubectl cluster-info

echo "license=$GDCN_LICENSE" > gooddata-license.env

if [ "$CREATE_CLUSTER" ]; then
  # Wait for cert-manager. Kubectl is completely happy when listing
  # resources in non-existent namespace but it fails when waiting
  # on non-existent resources if using selector. Therefore we must
  # poll for namespace and some specific resource first and then
  # we can wait for deployment to become available.
  echo "Waiting for cert-manager to come up"
  while ! kubectl get ns cert-manager &>/dev/null; do
    echo -n "."
    sleep 10
  done
  while ! kubectl -n cert-manager get deployment cert-manager &>/dev/null; do
    echo -n "."
    sleep 10
  done
  kubectl -n cert-manager wait deployment --for=condition=available \
    --selector=app.kubernetes.io/instance=cert-manager \
    --timeout=240s
  echo "Done"
  # This script generates key/cert pair (if not already available).
  # If the pair is already available, it will reuse it.
  # Key, certificate, and issuer will be loaded by kustomize
  ./gen_keys.sh -k
fi

# Generate manifests by kustomize, substitute env variables, and apply
# shellcheck disable=SC2016
kubectl kustomize . |
  PULSAR_CHART_VERSION=$PULSAR_CHART_VERSION \
    DOCKER_REGISTRY_PORT=$DOCKER_REGISTRY_PORT \
    PULSAR_VERSION=$PULSAR_VERSION \
    envsubst '$DOCKER_REGISTRY_PORT $PULSAR_CHART_VERSION $PULSAR_VERSION' |
  kubectl apply -f -

if [ -n "$VALUES_FILE" ]; then
  echo "Deploying GD.CN with values file $VALUES_FILE"
fi

# deployVisualExporter=false: visualExporterService is not supported in k3d deployment now because:
#  - chromium is not able to load dashboard on internal domain (some /etc/hosts magic has to be done there)
#  - chromium container in visualExporterChromium service is not multiarch and needs to be built manually for arm64
v helm -n gooddata upgrade --install gooddata-cn \
  --repo https://charts.gooddata.com --version "$GDCN_VERSION" \
  --wait --timeout 10m \
  ${VALUES_FILE:+--values $VALUES_FILE} \
  --set image.repositoryPrefix=$REPOSITORY_PREFIX \
  --set ingress.lbProtocol=https --set ingress.lbPort="$LBSSLPORT" \
  --set replicaCount=1 --set dex.ingress.annotations."cert-manager\.io/issuer"=ca-issuer \
  --set dex.ingress.tls.authSecretName=gooddata-cn-dex-tls \
  --set metadataApi.encryptor.enabled=false \
  --set license.existingSecret=gdcn-license-key gooddata-cn

cat <<EOF
Ingress available on http://localhost${LBPORT:+:$LBPORT}/ and https://localhost${LBSSLPORT:+:$LBSSLPORT}/

If you want using HTTPS endpoints, install CA certificate to your system as described
above.

EOF

popd
