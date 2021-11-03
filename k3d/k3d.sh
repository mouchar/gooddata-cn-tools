#!/usr/bin/env bash
# (C) 2021 GoodData Corporation
#
# Create K3D cluster with Pulsar and GoodData.CN Helm charts deployed.
# Requirements
# * running docker daemon, containers must be able to access the Internet
# * docker client
# * k3d v3.1.0+
# * helm v3.5+
# * kubectl 1.18+
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
# -H authHost : Sets public hostname for Dex Oauth2 provider. Defaults to
#               localhost, which makes it convenient for local deployment. If
#               you plan to deploy on remote instance, set it to publicly
#               accessible hostname.
set -e
PULSAR_VERSION="2.7.2"
PULSAR_CHART_VERSION="${PULSAR_VERSION}"
# PC-3617 GoodData PI pool banned by apache.org, we can't access their helm chart repo
PULSAR_REPO="https://github.com/apache/pulsar-helm-chart"
PULSAR_URL="${PULSAR_REPO}/releases/download/pulsar-${PULSAR_CHART_VERSION}/pulsar-${PULSAR_CHART_VERSION}.tgz"

# Update to newer version when available
GOODDATA_CN_VERSION="1.4.0"
CLUSTER_NAME="default"
# set to empty string if you want port 80
LBPORT=""
# set to empty string if you want port 443
LBSSLPORT=""

# Check the license key variable
if [ -z "$GDCN_LICENSE" ] ; then
    cat > /dev/stderr <<EOT
    The env variable GDCN_LICENSE must be set and it must contain a valid
    license key for GoodData.CN
EOT
    exit 1
fi

usage() {
    cat > /dev/stderr <<EOT
    Usage: $0 [options]
    Options are:
      -c - create cluster
      -H authHost - public hostname for Dex [default: localhost]
      -p registryPort - port of local docker registry [default: 5050]
EOT
    exit 1
}

v() {
    echo Running: $@
    $@
}

prepare_registry() {
  echo "Checking for local docker registry volume"
  docker volume inspect registry-data -f "{{.Name}}" || docker volume create registry-data

  registry_running=`docker container inspect k3d-registry -f '{{.State.Running}}' || :`
  if [ -z "$registry_running" ] ; then
    echo "Registry container doesn't exist, running the new registry container."
    docker container run -d --name k3d-registry -v registry-data:/var/lib/registry --restart always -p ${registryPort}:5000 registry:2
  elif [ "$registry_running" == "false" ] ; then
    echo "Registry container stopped, starting."
    docker container start k3d-registry
  else
    echo "Docker registry is already running"
  fi
}

CREATE_CLUSTER=""
authHost="localhost"
# Port 5000 is apparently occupied on OSX/Windows
registryPort="5050"

while getopts "cH:" o; do
    case "${o}" in
        c)
            CREATE_CLUSTER=yes
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

echo "Checking for missing tools"
k3d version
helm version
kubectl version --client
docker ps -q > /dev/null

cd $(dirname $0)

# This is needed to make kubedns working in pods running on the same host
# where kubedns pod is running; valid for Linux
if [[ $(uname) != *"Darwin"* ]];then
  echo "Checking bridge netfilter policy"
  if ! grep -q 1 /proc/sys/net/bridge/bridge-nf-call-iptables ; then
      echo "Enabling bridge-nf-call-iptables"
      echo '1' | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables
  fi
fi

# Create cluster
if [ "$CREATE_CLUSTER" ] ; then
    docker network disconnect k3d-$CLUSTER_NAME k3d-registry || :
    k3d cluster delete $CLUSTER_NAME || :
    prepare_registry
    k3d cluster create $CLUSTER_NAME --agents 2 --api-port 0.0.0.0:6443 -p "${LBPORT:-80}:80@loadbalancer" \
      -p "${LBSSLPORT:-443}:443@loadbalancer" \
      --k3s-server-arg '--no-deploy=traefik' \
      --volume "$PWD/registries.yaml:/etc/rancher/k3s/registries.yaml" \
      --volume "$PWD/cert-manager.yaml:/var/lib/rancher/k3s/server/manifests/cert-manager.yaml" \
      --volume "$PWD/ingress-nginx.yaml:/var/lib/rancher/k3s/server/manifests/ingress-nginx.yaml"
    echo "Attaching registry container to k3d-$CLUSTER_NAME network"
    docker network connect --alias registry.local k3d-$CLUSTER_NAME k3d-registry || exit 1
    k3d kubeconfig merge default -d
    kubectl config use-context k3d-$CLUSTER_NAME
fi

echo "Creating namespaces"
kubectl apply -f - <<EOT
apiVersion: v1
kind: List
items:
- apiVersion: v1
  kind: Namespace
  metadata:
    name: pulsar
    labels:
      metadata.labels.kubernetes.io/metadata.name: pulsar
- apiVersion: v1
  kind: Namespace
  metadata:
    labels:
      metadata.labels.kubernetes.io/metadata.name: gooddata
    name: gooddata
EOT

echo "Pre-pulling images from DockerHub to local registry."
apps=(
    afm-exec-api auth-service metadata-api result-cache scan-model sql-executor
    aqe tools organization-controller dex analytical-designer dashboards home-ui
    ldm-modeler measure-editor apidocs
    )
for app in "${apps[@]}" ; do
    echo " == $app"
    docker pull -q gooddata/${app}:${GOODDATA_CN_VERSION}
    docker tag gooddata/${app}:${GOODDATA_CN_VERSION} localhost:${registryPort}/${app}:${GOODDATA_CN_VERSION}
    docker push -q localhost:${registryPort}/${app}:${GOODDATA_CN_VERSION}
done

# Preload pulsar to local registry
# The reason is that it is a huge image and DockerHub token expires before the image
# is pulled by containerd. Furthermore, is is pulled 3-4 times in parallel.
docker pull -q apachepulsar/pulsar:$PULSAR_VERSION
docker tag apachepulsar/pulsar:$PULSAR_VERSION localhost:${registryPort}/apachepulsar/pulsar:$PULSAR_VERSION
docker push -q localhost:${registryPort}/apachepulsar/pulsar:$PULSAR_VERSION

kubectl config use-context k3d-$CLUSTER_NAME
kubectl cluster-info

if [ "$CREATE_CLUSTER" ] ; then
  # Wait for cert-manager. Kubectl is completely happy when listing
  # resources in non-existent namespace but it fails when waiting
  # on non-existent resources if using selector. Therefore we must
  # poll for namespace and some specific resource first and then
  # we can wait for deployment to become available.
  echo "Waiting for cert-manager to come up"
  while ! kubectl get ns cert-manager &> /dev/null ; do
    sleep 10
  done
  while ! kubectl -n cert-manager get deployment cert-manager &> /dev/null ; do
    sleep 10
  done
  kubectl -n cert-manager wait deployment --for=condition=available \
      --selector=app.kubernetes.io/instance=cert-manager

#  pushd deployment/k3d
  # This script generates key/cert pair (if not already available),
  # stores it in secret gooddata/ca-key-pair and registers local
  # CA as a new cert-manager Issuer gooddata/ca-issuer
  ./gen_keys.sh
#  popd
fi

echo "Adding missing Helm repositories"
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
  configData:
    PULSAR_MEM: >
      -Xms128m -Xmx256m -XX:MaxDirectMemorySize=128m
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
    repository: registry.local:5000/apachepulsar/pulsar
  bookie:
    tag: $PULSAR_VERSION
    repository: registry.local:5000/apachepulsar/pulsar
  broker:
    tag: $PULSAR_VERSION
    repository: registry.local:5000/apachepulsar/pulsar
  zookeeper:
    tag: $PULSAR_VERSION
    repository: registry.local:5000/apachepulsar/pulsar
pulsar_metadata:
  image:
    tag: $PULSAR_VERSION
    repository: registry.local:5000/apachepulsar/pulsar
EOT

if [ "$CREATE_CLUSTER" ] ; then
  initialize="--set initialize=true"
fi

# Install Apache Pulsar helm chart
v helm -n pulsar upgrade --wait --timeout 7m --install pulsar \
    --values /tmp/values-pulsar-k3d.yaml $initialize --version $PULSAR_CHART_VERSION ${PULSAR_URL}

cat << EOT > /tmp/values-gooddata-cn.yaml
replicaCount: 1
authService:
  allowRedirect: https://localhost:8443
cookiePolicy: None
dex:
  ingress:
    authHost: $authHost
    annotations:
      cert-manager.io/issuer: ca-issuer
    tls:
      authSecretName: gooddata-cn-dex-tls
image:
  repositoryPrefix: registry.local:5000
cacheGC:
  image:
    name: registry.local:5000/apachepulsar/pulsar
ingress:
  annotations:
    nginx.ingress.kubernetes.io/cors-allow-headers: X-GDC-JS-SDK-COMP, X-GDC-JS-SDK-COMP-PROPS, X-GDC-JS-PACKAGE, X-GDC-JS-PACKAGE-VERSION, x-requested-with, X-GDC-VALIDATE-RELATIONS, DNT, X-CustomHeader, Keep-Alive, User-Agent, X-Requested-With, If-Modified-Since, Cache-Control, Content-Type, Authorization
    nginx.ingress.kubernetes.io/cors-allow-origin: https://localhost:8443
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
license:
  key: "$GDCN_LICENSE"
EOT

# Install GoodData.CN Helm chart
v helm -n gooddata upgrade --install gooddata-cn --wait --timeout 7m \
    --values /tmp/values-gooddata-cn.yaml --version ${GOODDATA_CN_VERSION} \
    gooddata/gooddata-cn

cat << EOF
Ingress available on http://localhost${LBPORT:+:$LBPORT}/ and https://localhost${LBSSLPORT:+:$LBSSLPORT}/

If you wan't using HTTPS endpoints, install CA certificate to your system as described
above.

EOF
