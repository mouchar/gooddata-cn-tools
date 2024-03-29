#!/usr/bin/env bash
# (C) 2021 GoodData Corporation
#
# Create K3D cluster with Pulsar and GoodData.CN Helm charts deployed.
# Requirements
# * running docker daemon, containers must be able to access the Internet
# * docker client
# * k3d v4.4.8+ (version v5.x preferred)
# * helm v3.5+
# * kubectl 1.21+
#
# helm, k3d and kubectl can be installed using gofish:
# curl -fsSL https://raw.githubusercontent.com/fishworks/gofish/main/scripts/install.sh | bash
# gofish init
# gofish install kubectl helm k3d
#
# The environment variable GDCN_LICENSE needs to be set and it must contain
# a valid license key for GoodData.CN
#
# Parameters:
# -c          : Create cluster - when k3d cluster already exists, it is deleted
#                (local docker registry is preserved)
# -n          : Do not expose SSL port. Only port 80 (or $LBPORT) can be used for
#               exposing k8s apps using Ingress. Cert-manager and TLS stuff will
#               not be installed.
# -H authHost : Sets public hostname for Dex Oauth2 provider. Defaults to
#               localhost, which makes it convenient for local deployment. If
#               you plan to deploy on remote instance, set it to publicly
#               accessible hostname.
set -e
# Version of Pulsar image
PULSAR_VERSION="2.7.4"
# Version of Pulsar Helm chart
PULSAR_CHART_VERSION="2.7.8"

# Update to newer version when available
GOODDATA_CN_VERSION="1.7.0"
CLUSTER_NAME="default"
# set to empty string if you want port 80
LBPORT=""
# set to empty string if you want port 443. Ignored with (-n) paramter
LBSSLPORT=""

# LBPORT="8080"
# LBSSLPORT="3443"

CREATE_CLUSTER=""
# Comment chars for ssl-specific settings in manifests
NO_SSL=""
SSL="#"
authHost="localhost"
# Port 5000 is apparently occupied on OSX/Windows
registryPort="5050"

### Functions
usage() {
    cat > /dev/stderr <<EOT
    Create k3d cluster with GoodData.CN installed.

    Usage: $0 [options]
    Options are:
      -c              - create cluster
      -n              - do not use SSL port
      -H authHost     - public hostname for Dex [default: localhost]
      -p registryPort - port of local docker registry [default: 5050]
EOT
    exit 1
}

v() {
    echo Running: "$@"
    "$@"
}

prepare_registry() {
  echo "🐋 Checking for local docker registry volume"
  docker volume inspect registry-data -f "{{.Name}}" || docker volume create registry-data

  registry_running=$(docker container inspect k3d-registry -f '{{.State.Running}}' || :)
  # Check docker registry labels - new k3d expects proper lables to be set
  if [ -n "$registry_running" ] ; then
    port_label=$(docker inspect k3d-registry -f '{{index .Config.Labels "k3s.registry.port.external"}}')
    if [ "$port_label" != "${registryPort}" ] ; then
      echo "Outdated local docker registry found, recreating."
      docker rm -f k3d-registry
      registry_running=''
    fi
  fi
  if [ -z "$registry_running" ] ; then
    echo "Registry container doesn't exist, running the new registry container."
    docker container run -d --name k3d-registry -v registry-data:/var/lib/registry \
      --restart always -p "${registryPort}":5000 -l app=k3d -l k3d.cluster= \
      -l k3d.registry.host= -l k3d.registry.hostIP=0.0.0.0 -l k3d.role=registry \
      -l k3d.version=5.2.1 -l k3s.registry.port.external="${registryPort}" \
      -l k3s.registry.port.internal=5000 registry:2
  elif [ "$registry_running" == "false" ] ; then
    echo "Registry container stopped, starting."
    docker container start k3d-registry
  else
    echo "Docker registry is already running"
  fi
}

pull_images() {
  echo "Pre-pulling images from DockerHub to local registry."
  apps=(
      afm-exec-api auth-service metadata-api result-cache scan-model sql-executor
      aqe tools organization-controller dex analytical-designer dashboards home-ui
      ldm-modeler measure-editor apidocs calcique
      )
  for app in "${apps[@]}" ; do
      echo " == $app"
      docker pull -q "gooddata/${app}:${GOODDATA_CN_VERSION}"
      docker tag "gooddata/${app}:${GOODDATA_CN_VERSION}" "localhost:${registryPort}/${app}:${GOODDATA_CN_VERSION}"
      docker push -q "localhost:${registryPort}/${app}:${GOODDATA_CN_VERSION}"
  done

  # Preload pulsar to local registry
  # The reason is that it is a huge image and DockerHub token expires before the image
  # is pulled by containerd. Furthermore, is is pulled 3-4 times in parallel.
  docker pull -q "apachepulsar/pulsar:$PULSAR_VERSION"
  docker tag "apachepulsar/pulsar:$PULSAR_VERSION" "localhost:${registryPort}/apachepulsar/pulsar:$PULSAR_VERSION"
  docker push -q "localhost:${registryPort}/apachepulsar/pulsar:$PULSAR_VERSION"
}

### Start of script

# Check the license key variable
if [ -z "$GDCN_LICENSE" ] ; then
    cat > /dev/stderr <<EOT
    The env variable GDCN_LICENSE must be set and it must contain a valid
    license key for GoodData.CN
EOT
    exit 1
fi

while getopts "cnH:p:" o; do
    case "${o}" in
        c)
            CREATE_CLUSTER=yes
            ;;
        n)
            # reverse the comment chars
            NO_SSL='#'
            SSL=''
            ;;
        H)
            authHost="${OPTARG}"
            ;;
        p)
            registryPort="${OPTARG}"
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if ! [[ "$registryPort" =~ ^[1-9][0-9]*$ && "$registryPort" -lt 65536 ]] ; then
  echo "🔥 Invalid registry port '$registryPort', positive integer reqiured"
  exit 1
fi

echo "🔎 Checking for missing tools"
k3d version
helm version
kubectl version --client
docker ps -q > /dev/null

cd "$(dirname "$0")"

# This is needed to make kubedns working in pods running on the same host
# where kubedns pod is running; valid for Linux
if [[ $(uname) != *"Darwin"* ]];then
  echo "🔎 Checking bridge netfilter policy"
  if ! grep -q 1 /proc/sys/net/bridge/bridge-nf-call-iptables ; then
      echo "  Enabling bridge-nf-call-iptables"
      echo '1' | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables
  fi
fi

# Create cluster
if [ -n "$CREATE_CLUSTER" ] ; then
    k3d cluster delete $CLUSTER_NAME || :
    prepare_registry
    v k3d cluster create -c /dev/stdin <<EOT
apiVersion: k3d.io/v1alpha3
kind: Simple
name: default
servers: 1
agents: 2
kubeAPI:
  hostIP: "0.0.0.0"
  hostPort: "6443"
image: rancher/k3s:v1.21.7-k3s1
${NO_SSL}volumes:
${NO_SSL}  - volume: $PWD/cert-manager.yaml:/var/lib/rancher/k3s/server/manifests/cert-manager.yaml
${NO_SSL}    nodeFilters:
${NO_SSL}      - server:0
ports:
  - port: ${LBPORT:-80}:${LBPORT:-80}
    nodeFilters:
      - loadbalancer
${NO_SSL}  - port: ${LBSSLPORT:-443}:${LBSSLPORT:-443}
${NO_SSL}    nodeFilters:
${NO_SSL}      - loadbalancer
registries:
  use:
    - k3d-registry:5000
options:
  k3s:
    extraArgs:
      - arg: --disable=traefik
        nodeFilters:
          - server:*
  kubeconfig:
    updateDefaultKubeconfig: true
    switchCurrentContext: true
EOT
    echo "✅ k3d cluster successfully created."
fi

echo "📁 Creating namespaces"
kubectl apply -f namespaces.yaml

echo "🌎 Installing Ingress Controller"
kubectl apply -f - <<EOT
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: ingress-nginx
  namespace: kube-system
spec:
  repo: https://kubernetes.github.io/ingress-nginx
  chart: ingress-nginx
  version: 4.0.13
  targetNamespace: kube-system
  valuesContent: |-
    controller:
      config:
        use-forwarded-headers: "true"
        # If you plan to put reverse proxy in front of k3d cluster,
        # you may want to disable ssl-redirect here:
        ${SSL}ssl-redirect: "false"
      tolerations:
      - key: "node-role.kubernetes.io/master"
        operator: "Exists"
        effect: "NoSchedule"
      service:
        ports:
          http: ${LBPORT:-80}
          https: ${LBSSLPORT:-443}
EOT

[ -z "$SKIP_PULL" ] && pull_images
kubectl config use-context k3d-$CLUSTER_NAME
kubectl cluster-info

if [ -n "$CREATE_CLUSTER" ] && [ -n "$SSL" ] ; then
  # Wait for cert-manager. Kubectl is completely happy when listing
  # resources in non-existent namespace but it fails when waiting
  # on non-existent resources if using selector. Therefore we must
  # poll for namespace and some specific resource first and then
  # we can wait for deployment to become available.
  echo "🔐 Waiting for cert-manager to come up"
  while ! kubectl get ns cert-manager &> /dev/null ; do
    sleep 10
  done
  while ! kubectl -n cert-manager get deployment cert-manager &> /dev/null ; do
    sleep 10
  done
  kubectl -n cert-manager wait deployment --for=condition=available \
      --selector=app.kubernetes.io/instance=cert-manager

  # This script generates key/cert pair (if not already available),
  # stores it in secret gooddata/ca-key-pair and registers local
  # CA as a new cert-manager Issuer gooddata/ca-issuer
  ./gen_keys.sh
fi

echo "📦 Adding missing Helm repositories"
helm repo add pulsar https://pulsar.apache.org/charts
helm repo add gooddata https://charts.gooddata.com/

helm repo update

cat << EOT > /tmp/values-pulsar-k3d.yaml
components:
  functions: false
  proxy: false
  pulsar_manager: false
  toolset: false
monitoring:
  alert_manager: false
  grafana: false
  node_exporter: false
  prometheus: false
bookkeeper:
  replicaCount: 3
  resources:
    requests:
      cpu: 0.2
      memory: 128Mi
broker:
  configData:
    PULSAR_MEM: >
      -Xms128m -Xmx256m -XX:MaxDirectMemorySize=128m
    subscriptionExpirationTimeMinutes: "5"
    webSocketServiceEnabled: "true"
  replicaCount: 2
  resources:
    requests:
      cpu: 0.2
      memory: 256Mi
volumes:
  persistence: false
images:
  autorecovery:
    tag: $PULSAR_VERSION
    repository: k3d-registry:5000/apachepulsar/pulsar
  bookie:
    tag: $PULSAR_VERSION
    repository: k3d-registry:5000/apachepulsar/pulsar
  broker:
    tag: $PULSAR_VERSION
    repository: k3d-registry:5000/apachepulsar/pulsar
  zookeeper:
    tag: $PULSAR_VERSION
    repository: k3d-registry:5000/apachepulsar/pulsar
pulsar_metadata:
  image:
    tag: $PULSAR_VERSION
    repository: k3d-registry:5000/apachepulsar/pulsar
EOT

if [ -n "$CREATE_CLUSTER" ] ; then
  initialize=(--set initialize=true)
fi

# Install Apache Pulsar helm chart
echo "📨 Installing Apache Pulsar"
v helm -n pulsar upgrade --wait --timeout 7m --install pulsar \
    --values /tmp/values-pulsar-k3d.yaml "${initialize[@]}" \
    --version $PULSAR_CHART_VERSION apache/pulsar

cat << EOT > /tmp/values-gooddata-cn.yaml
replicaCount: 1
authService:
  allowRedirect: https://localhost:8443
cookiePolicy: None
dex:
  ingress:
    authHost: $authHost
    ${NO_SSL}annotations:
    ${NO_SSL}  cert-manager.io/issuer: ca-issuer
    ${NO_SSL}tls:
    ${NO_SSL}  authSecretName: gooddata-cn-dex-tls
image:
  repositoryPrefix: k3d-registry:5000
ingress:
  annotations:
    nginx.ingress.kubernetes.io/cors-allow-headers: X-GDC-JS-SDK-COMP, X-GDC-JS-SDK-COMP-PROPS, X-GDC-JS-PACKAGE, X-GDC-JS-PACKAGE-VERSION, x-requested-with, X-GDC-VALIDATE-RELATIONS, DNT, X-CustomHeader, Keep-Alive, User-Agent, X-Requested-With, If-Modified-Since, Cache-Control, Content-Type, Authorization
    nginx.ingress.kubernetes.io/cors-allow-origin: https://localhost:8443
    nginx.ingress.kubernetes.io/enable-cors: "true"
license:
  key: "$GDCN_LICENSE"
EOT

# Install GoodData.CN Helm chart
echo "📈 Installing GoodData.CN"
v helm -n gooddata upgrade --install gooddata-cn --wait --timeout 7m \
    --values /tmp/values-gooddata-cn.yaml --version ${GOODDATA_CN_VERSION} \
    gooddata/gooddata-cn

[ -n "$CREATE_CLUSTER" ] && [ -n "$SSL" ] && ssl_ingress="and https://localhost${LBSSLPORT:+:$LBSSLPORT}/

If you want to use HTTPS endpoints, install CA certificate to your system as described
above."

cat << EOT

Ingress is available at http://localhost${LBPORT:+:$LBPORT}/ $ssl_ingress

EOT
