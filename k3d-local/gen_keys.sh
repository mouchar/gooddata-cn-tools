#!/bin/bash

# Creates local CA key/cert pair and configures cert-manager
# Issuer or ClusterIssuer (in case the namespace=cert-manager)
# Usage: $0 [namespace]
# Namespace defaults to "gooddata"

usage() {
    cat > /dev/stderr <<EOT
    Usage: $0 [options] [namespace]
    Options are:
      -k - resources will be loaded later by kustomize

EOT
    exit 1
}

while getopts ":k" o; do
    case "${o}" in
        k)
            NO_LOAD=yes
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

NAMESPACE=${1-gooddata}
COMMON_NAME="K3D Local CA"
CM_NAMESPACE="cert-manager"
CLUSTERWIDE=""

if [ "${NAMESPACE}" == "${CM_NAMESPACE}" ] ; then
    echo "Given namespace is ${NAMESPACE}, creating ClusterIssuer"
    CLUSTERWIDE="Cluster"
fi

if [ ! -f ca.key ] ; then
    # Generate a CA private key
    openssl genrsa -out ca.key 2048
else
    echo "Reusing existing private key ca.key"
fi

if [ ! -f ca.crt ] ; then
    # Create a self signed Certificate, valid for 10yrs with the 'signing' option set
    openssl req -x509 -new -nodes -key ca.key -subj "/CN=${COMMON_NAME}" \
        -days 7300 -reqexts v3_req -extensions v3_ca -out ca.crt
else
    echo "Reusing existing CA certificate ca.crt"
fi

cat << EOF

If you wan't to suppress 'Untrusted certificate' errors in web browser,
install the following CA certificate to your system and browser:

$(cat ca.crt)

### On Linux with Chrome/Chromium browser, you can use this
### to set trust (needs libnss3-tools)
## sudo apt-get install libnss3-tools
### Create NSS db if it doesn't exist
## [ ! -d $HOME/.pki/nssdb ] && certutil -N -d sql:$HOME/.pki/nssdb --empty-password
## Load local CA Certificate as trusted to your system
## certutil -d sql:$HOME/.pki/nssdb -A -t C -n "$COMMON_NAME" -i $PWD/ca.crt

EOF

if [ "${NO_LOAD}" == "yes" ] ; then
    echo "Skipping upload to cluster"
    exit 0
fi

# MacOS has changed base64's command argument from version 13+ (Ventura)
case "$(uname -s)" in
    Darwin*)
        if [ $(sw_vers -productVersion | cut -d '.' -f 1) -ge 13 ] ; then
          b64_opts="-i"
        else
          b64_opts="-b0"
        fi
        ;;
    *)
        b64_opts="-w0"
        ;;
esac

cert=$(base64 $b64_opts ca.crt)
key=$(base64 $b64_opts ca.key)

# Create Secret
cat > ca-secret.yaml << EOF
apiVersion: v1
kind: Secret
type: kubernetes.io/tls
metadata:
  name: ca-key-pair
  namespace: ${NAMESPACE}
data:
  tls.crt: $cert
  tls.key: $key
EOF

# Create Issuer
cat > ca-issuer.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ${CLUSTERWIDE}Issuer
metadata:
  name: ca-issuer
  namespace: ${NAMESPACE}
spec:
  ca:
    secretName: ca-key-pair
EOF

echo "Uploading resources to kuberenetes"
kubectl create -f ca-secret.yaml
kubectl create -f ca-issuer.yaml

rm ca-issuer.yaml ca-secret.yaml
