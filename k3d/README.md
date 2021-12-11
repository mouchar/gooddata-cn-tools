# GoodData.CN in K3D
This script allows you to deploy a 3-node Kubernetes cluster on your local
machine within docker containers, deploy Apache Pulsar and GoodData.CN,
configure cert-manager with self-signed certificate authority and set up
Ningx ingress controller.

## Requirements

HW requirements are pretty high, I recommend at least 8 CPU cores and 12 GB
RAM available to Docker. Only `x86_64` CPU architecture is supported.

Here is a list of things you need to have installed before running the script:
* [k3d](https://github.com/rancher/k3d/releases/tag/v4.4.8) 4.x
* [kubectl](https://kubernetes.io/docs/tasks/tools/) 1.19 or higher
* openssl 1.x
* [Helm](https://helm.sh/docs/intro/install/) 3.x
* [Docker](https://www.docker.com/)

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
      -H authHost - public hostname for Dex [default: localhost]
      -p registryPort - port of local docker registry [default: 5050]
```

The option `-H authHost` is useful for deploying in public cloud, where the
cloud VM has some DNS alias.

The option `-p registryPort` allows you to customize port where local insecure
registry runs. This registry is used for local image caching to save bandwidth
during installation.

`-c` should be used to create or recreate cluster. If you want just update
existing cluster, do not use this parameter. Script will perform helm upgrade
of all components within existing cluster.

## Usage
```
./k3d.sh -c -H demo-auth.example.com
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
k3d-default-agent-1    Ready    <none>                 33m   v1.20.6+k3s1
k3d-default-server-0   Ready    control-plane,master   33m   v1.20.6+k3s1
k3d-default-agent-0    Ready    <none>                 33m   v1.20.6+k3s1
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
  hostname: demo.example.com
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
**Note**: We assume that both hostnames used in the example above
(`demo-auth.example.com` and `demo.example.com`) are resolvable on the client
you are using for access. This can be done using DNS records or adding a proper
line to your `/etc/hosts`, `/private/etc/hosts` or
`c:\Windows\System32\Drivers\etc\hosts`.

**Note 2**: As the system is using self-signed CA, you may also want to add its
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
  https://demo.example.com/api/entities/admin/organizations/demo

{
  "data": {
    "attributes": {
      "name": "Demo organization",
      "hostname": "demo.example.com",
      "oauthClientId": "114f0a8b-2335-4bf4-ba54-37e1ee04afe1"
    },
    "id": "demo",
    "type": "organization"
  },
  "links": {
    "self": "https://demo.example.com/api/entities/admin/organizations/demo"
  }
}
```

## Next steps
Follow the [documentation](https://www.gooddata.com/developers/cloud-native/doc)
to learn more about adding users, configuring data sources and further steps.

## Running k3d cluster behind reverse proxy
The k3d cluster has ports 80 and 443 exposed to ingress-nginx controller. While this
setup covers the most usual use cases, it is possible that you want these ports
to be changed for some reason. For example, you may want to have k3d cluster hidden
behind reverse proxy that listens on these two ports so they are not available:

```

+------+     +------------+    +--------------+    +----------------+    +-------------+
| User | ->  |*:443 nginx | -> |*:3443 k3d-lb | -> |k3d-server:3443 | -> | ingress-ctl |
+------+     +------------+    +--------------+    +----------------+    +-------------+
                   |                                                            |
                   v                                                            v
             +-------------+                                               +---------+
             |:3000 ext.app|                                               | k8s app |
             +-------------+                                               +---------+

```

In this case, the [k3d.sh](k3d.sh) script needs to be modified. There are two variables `LBPORT`
and `LBSSLPORT`. They are empty by default, meaning the internal k3d load balancer will listen on
default ports for given protocol (80 for http, 443 for https). You may change them to any other
port available on your docker host (except port 6443 that is used for k8s api). This setup will
allow you to free up default ports 80/443 for reverse proxy. There is one important drawback:
Due to some limitation in Ingress controller, the `X-Forwarded-Port` header that is send to k8s
services always contains value `443` unless this header is present in the incomming request.

When you access k8s services through reverse proxy, it should not be an issue, because well-configured
reverse proxies usually set this header to value to port where they actually received the incoming
request. But if you plan to access GoodData.CN **directly** on your custom ports (`3443` in the example above),
make sure your client sets this header to `3443` before sending requests. Otherwise, the internal
authentication will not work because OAuth2 redirect_url will not match preconfigured value.

Running k3d behind reverse proxy is therefore possible, but you will be responsible for TLS certificate
management on reverse proxy.

## Cleanup
If you want to wipe the environment, perform these steps:
* stop and delete local Docker registry: `docker rm -f k3d-registry`
* remove registry volume: `docker volume rm registry-data`
* delete k3d cluster: `k3d cluster delete default`
