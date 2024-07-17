g GoodData.CN in K3D
This script allows you to deploy a 3-node Kubernetes cluster on your local
machine within docker containers, deploy Apache Pulsar and GoodData.CN,
configure cert-manager with self-signed certificate authority and set up
Ningx ingress controller.

## Requirements

HW requirements are pretty high, I recommend at least 8 CPU cores and 12 GB
RAM available to Docker. Only `x86_64` CPU architecture is supported.

Here is a list of things you need to have installed before running the script:
* [k3d](https://github.com/rancher/k3d/releases/tag/v5.4.0) 5.4,x
* [kubectl](https://kubernetes.io/docs/tasks/tools/) 1.24 or higher
* openssl 1.x
* [Helm](https://helm.sh/docs/intro/install/) 3.x
* [Docker](https://www.docker.com/)
* envsubst (part of gettext)
* (optional but recommended) [crane](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md)

Environment variables that need to be set:
* `GDCN_LICENSE` contaning GoodData.CN license key

These services must be running and accessible by the user running the script:
* Docker daemon

Store your GoodData.CN license to environment variable GDCN_LICENSE:
```
export GDCN_LICENSE="key/......."
```

## Configuration
```
    Usage: ./k3d.sh [options]
    Options are:
      -c - create cluster
      -v VERSION - use this version of gooddata-cn helm chart
      -f FILE - full path to a yaml with GD.CN helm values
```

`-c` should be used to create or recreate cluster. If you want just update
existing cluster, do not use this parameter. Script will perform helm upgrade
of all components within existing cluster.

## Usage
```
./k3d.sh -c
```
The script pulls all images to local docker registry (to save network
bandwidth), creates 3-node kubernetes cluster, install apps, generates
CA certificate (the certificate is printed to output including the steps
describing how to add this certificate to your browser).

When script finishes, your kubeconfig is automatically set to your new
k3d cluster context. You can immediately use `kubectl` to control the cluster.

```
kubectl get node
NAME                   STATUS   ROLES                  AGE   VERSION
k3d-default-agent-1    Ready    <none>                 33m   v1.26.6+k3s1
k3d-default-server-0   Ready    control-plane,master   33m   v1.26.6+k3s1
k3d-default-agent-0    Ready    <none>                 33m   v1.26.6+k3s1
```

## What next?
Create Organization resource, and apply to cluster:

```
# contents of org-demo.yaml file
apiVersion: controllers.gooddata.com/v1
kind: Organization
metadata:
  name: demo-org
  namespace: gooddata
spec:
  id: demo
  name: Demo organization
  hostname: localhost
  adminGroup: adminGroup
  adminUser: admin
  adminUserToken: "$5$marO0ghT5pAg/CLe$ZiGVePUEPHryyEpSnnd9DmbLs4uNUKWGXjjmGnYT1NA"
  tls:
    secretName: demo-org-tls
    issuerName: ca-issuer
```

Explanation of important attributes:
* `metadata.name` - name of Kubernetes resource
* `metadata.namespace` - where the Organization resource  will be created
* `spec.id` - ID of organization in metadata
* `spec.name` - friendly name of organization
* `spec.hostname` - FQDN of organization endpoint. Ingress with the same host will be
  created by the GoodData.CN
* `spec.adminUser` - name of initial organization administrator account
* `spec.adminUserToken` - SHA256 hash (salted) of the secret part of bootstrap
  token
* `spec.tls.secretName` - name of k8s Secret where TLS certificate and key will
  be stored by cert-manager
* `spec.tls.issuerName` - name of cert-manager's Issuer or ClusterIsuer
* `spec.tls.issuerType` - type of cert-manager's issuer. Either `Issuer` (default)
  or `ClusterIssuer`.

The easiest way on how to generate salted hash from plaintext secret is:

```
docker run -it --rm alpine:latest mkpasswd -m sha256crypt example

$5$marO0ghT5pAg/CLe$ZiGVePUEPHryyEpSnnd9DmbLs4uNUKWGXjjmGnYT1NA
```

Apply organization resource:
```
kubectl apply -f org-demo.yaml
```

## Try accessing the organization
**Note**: As the system is using self-signed CA, you may also want to add its
certificate to your operating system and web browser.

To access organization for the first time, create so-called bootstrap token from
the secret you used to create `spec.adminUserToken` above. We used "example"
word as a secret, and "admin" as `spec.adminUser` account name. "bootstrap" is
given and can not be changed. Later on, you can create your own API tokens and
name them as you wish.

```
echo -n "admin:bootstrap:example" | base64
YWRtaW46Ym9vdHN0cmFwOmV4YW1wbGU=
```

So `YWRtaW46Ym9vdHN0cmFwOmV4YW1wbGU=` is your secret token you will use for
initial setup of the organization using JSON:API and REST API.

```
curl -k -H 'Authorization: Bearer YWRtaW46Ym9vdHN0cmFwOmV4YW1wbGU=' \
  https://localhost/api/v1/entities/admin/organizations/demo

{
  "data": {
    "attributes": {
      "name": "Demo organization",
      "hostname": "localhost",
      "oauthClientId": "114f0a8b-2335-4bf4-ba54-37e1ee04afe1"
    },
    "id": "demo",
    "type": "organization"
  },
  "links": {
    "self": "https://localhost/api/v1/entities/admin/organizations/demo"
  }
}
```

## Next steps
Follow the [documentation](https://www.gooddata.com/developers/cloud-native/doc)
to learn more about adding users, configuring data sources and further steps.

## Cleanup
If you want to wipe the environment, perform these steps:
* delete k3d cluster: `k3d cluster delete default`
* remove registry volume: `docker volume rm registry-data`
