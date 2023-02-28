# Support Bundle for GoodData.CN

## Installation
You need to install kubectl plugin `support_bundle` that is distributed using
`krew` plugin repository. Follow


In case of an unexpected situation with [GoodData.CN](https://www.gooddata.com/developers/cloud-native/)
Free, Growth and Enterprise which you are not able to resolve, you may be asked to provide logs from your
Kubernetes cluster for investigation of the issue.

This guide describes how to gather the logs using open source application, written by
[Replicated](https://www.replicated.com/). You can find the source code in [this repository](https://github.com/replicatedhq/troubleshoot)
and documentation [here](https://troubleshoot.sh/docs/collect/).

Sensitive data like secrets are not collected. Other potentially sensitive data (usernames, passwords, some IP addresses) are redacted.

## Prerequisites
Install krew plugin for kubectl:

```
curl -s https://krew.sh/support-bundle | bash
```

Set PATH for the krew plugin:

```
export PATH="${PATH}:${HOME}/.krew/bin"
```

## Runing support bundle
Download this configuration file [`support_bundle_gooddata_cn.yaml`](support_bundle_gooddata_cn.yaml) and review its contents. The file
contains pre-defined sets of collectors that have the following assumptions:
* GoodData.CN is installed in the namespace `gooddata-cn`
* Apache Pulsar is installed in the namespace `pulsar`
* Ingress controller for Kubernetes is installed in the namespace `ingress-nginx`
* Cert-manager is installed in the namespace `cert-manager`

In case your installation uses different namespaces, please update the configuration file.

Run support-bundle plugin with configuration file:
```
kubectl support-bundle support_bundle_gooddata_cn.yaml
```

## Collect the results
You will find a new file support-bundle-<<TIMESTAMP>>.tar.gz in the current directory. Send this file to GoodData support, when requested.

## Note
This guide is not applicable for GoodData.CN Community Edition, it only works on Kubernetes.


