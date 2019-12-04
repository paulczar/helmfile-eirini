# Helmfile Eirini

This project attempts to automate the installation of Cloud Foundry on top of Kubernetes via the Eirini project. It adds some optional components such as `nginx-ingress` and `cert-manager` to improve the automation of the infrastructure requirements.

Currently it should work for any Kubernetes cluster (tested on GKE and PKS) running on Google Cloud.

Helmfile is used as the deployment mechanism to tie multiple Helm Charts together and to provide a gitops style deployment workflow. it is expected that you'll have separate `env` directory(s) containing the customizations for a particular environment or cluster.

For the most part you should just need to edit `envs/example-gke/envs.sh` and fill it in with your details. This is a shell script that will export environment variables to be used by Helmfile. The reason for this is that if you have passwords/secrets you can store them outside of git and have the script extract them from wherever you keep them.

## Download tools

It's expected that you already have the basic Kubernetes client tools like `kubectl` installed.

### Helm

* [helm](https://helm.sh/docs/using_helm/#quickstart-guide)
* [helmfile](https://github.com/roboll/helmfile#installation)
* [helmdiff](https://github.com/databus23/helm-diff#install)

## Example GKE

This example shows installing Eirini to a GKE Cluster with a _Google managed DNS_ domain.

> Note: This also works with PKS running on Google Cloud, and likely any other Kubernetes cluster running on Google Cloud.

### Configuration

Poke through `envs/example-gke/envs.sh` it should be pretty obvious what you need to set. Ideally you'll copy this directory somewhere and modify and use it outside the scope of this git repository.

Change the following variables in `envs/example-gke/envs.sh`:

* `GOOGLE_PROJECT_ID`
* `EXTERNAL_DNS_DOMAIN`
* `EIRINI_BITS_SECRET`
* `EIRINI_ADMIN_PASSWORD`
* `EIRINI_ADMIN_CLIENT_SECRET`

Load the configuration into Environment Variables:

```console
. ./envs/example-gke/envs.sh
```

### Create GKE Cluster

> Note [skip](#create-a-gcp-service-account-for-dns-management) this section if you are running PKS on GCP and go straight to [creating a gcp service account for dns management](https://github.com/paulczar/helmfile-eirini#create-a-gcp-service-account-for-dns-management).

Create a GKE Cluster called `example-eirini`:

```console
gcloud container clusters create example-eirini \
  --num-nodes 5
```

Fetch your Kubernetes credentials:

```console
gcloud container clusters get-credentials example-eirini
```

Ensure you can access Kubernetes:

```console
$ kubectl get nodes
NAME                                            STATUS   ROLES    AGE   VERSION
gke-example-eirini-default-pool-67d0c7ee-41gt   Ready    <none>   11m   v1.13.10-gke.0
gke-example-eirini-default-pool-67d0c7ee-c53z   Ready    <none>   11m   v1.13.10-gke.0
gke-example-eirini-default-pool-67d0c7ee-m0v5   Ready    <none>   11m   v1.13.10-gke.0
```

### Create a DNS Zone

```console
gcloud dns managed-zones create eirini-$ENV_NAME \
  --dns-name $EXTERNAL_DNS_DOMAIN \
  --description "managed zone for eirini $ENV_NAME"
```

### Create a GCP service account for DNS management

Create service account:

```console
gcloud iam service-accounts create \
    eirini-dns --display-name "Eirini DNS Management"
```

Assign permissions:

```console
EMAIL=eirini-dns@$GOOGLE_PROJECT_ID.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $GOOGLE_PROJECT_ID \
  --member serviceAccount:$EMAIL --role roles/dns.admin
```

Download a google credentials file into your `envs/example-gke` directory:

```console
gcloud iam service-accounts keys create \
  envs/example-gke/key.json --iam-account=$EMAIL
```

### Install Tiller

This will install Helm's Tiller (somewhat) securely:

```bash
kubectl -n kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account=tiller
kubectl -n kube-system delete service tiller-deploy
kubectl -n kube-system patch deployment tiller-deploy --patch '
spec:
  template:
    spec:
      containers:
        - name: tiller
          ports: []
          command: ["/tiller"]
          args: ["--listen=localhost:44134"]
'
```

check tiller is working:

```bash
$ helm version
Client: &version.Version{SemVer:"v2.14.0", GitCommit:"05811b84a3f93603dd6c2fcfe57944dfa7ab7fd0", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.14.0", GitCommit:"05811b84a3f93603dd6c2fcfe57944dfa7ab7fd0", GitTreeState:"clean"}
```

### Install Eirini

Load up your environment's configuration:

```console
. ./envs/example-gke/envs.sh
```

Start by applying the `cert-manager` `CRDs`:

```console
kubectl apply --validate=false -f resources/cert-manager/crds.yaml
```

Run a `helmfile diff` to ensure there's no known errors:

```console
helmfile --state-values-file $ENV_DIR/values.yaml diff
```

If no errors are thrown go ahead and deploy:

```console
helmfile --state-values-file $ENV_DIR/values.yaml apply
```

### Sit back and wait for Eirini to get itself running

It can take some time for things to get running and ready for use.

Your first sign things are working is that `cert-manager`, `external-dns` and `nginx-ingress` are running in the `cluster-system` namespace:

```console
$ kubectl -n cluster-system get pods
NAME                                                     READY   STATUS    RESTARTS   AGE
cert-manager-646dbbccb8-m8bl5                            1/1     Running   0          3m38s
cert-manager-cainjector-7c5667645b-mp5sp                 1/1     Running   0          3m38s
external-dns-696974bccf-pzzhb                            1/1     Running   0          3m36s
ingress-nginx-ingress-controller-7mw6f                   1/1     Running   0          3m37s
ingress-nginx-ingress-controller-9nbt5                   1/1     Running   0          3m37s
ingress-nginx-ingress-controller-vn897                   1/1     Running   0          3m37s
ingress-nginx-ingress-default-backend-5f6f6bb6fc-wwlpw   1/1     Running   0          3m37s
```

Eventually UAA will be running in the `uaa` namespace:

```console
$ kubectl -n uaa get pods
NAME                        READY   STATUS      RESTARTS   AGE
mysql-0                     1/1     Running     0          31m
mysql-proxy-0               1/1     Running     0          33m
secret-generation-1-q9ms5   0/1     Completed   0          56m
uaa-0                       1/1     Running     0          14m
```

Validate UAA is listening:

```console
$ curl -s https://uaa.$EIRINI_DOMAIN/info | jq .app.version
"4.31.0-SNAPSHOT"
```

Next check on CF, eventually it will be ready:

```console
$ kubectl -n scf get pods
NAME                              READY   STATUS      RESTARTS   AGE
adapter-0                         2/2     Running     0          25m
api-group-0                       2/2     Running     0          23m
bits-849c78b94c-nw47k             1/1     Running     0          34m
blobstore-0                       2/2     Running     0          25m
cc-clock-0                        2/2     Running     0          2m47s
cc-uploader-0                     2/2     Running     0          25m
cc-worker-0                       2/2     Running     0          31m
cf-usb-group-0                    1/1     Running     0          31m
doppler-0                         2/2     Running     0          29m
eirini-7f46c48f57-6rs5j           1/1     Running     5          34m
locket-0                          2/2     Running     0          31m
log-api-0                         2/2     Running     0          30m
log-cache-scheduler-0             2/2     Running     0          31m
loggregator-fluentd-4w8zr         2/2     Running     0          33m
loggregator-fluentd-d9v6c         2/2     Running     0          33m
loggregator-fluentd-jd8vd         2/2     Running     0          33m
mysql-0                           1/1     Running     0          26m
nats-0                            2/2     Running     0          31m
nfs-broker-0                      1/1     Running     0          32m
post-deployment-setup-2-kmgq8     0/1     Completed   0          34m
rootfs-patcher-v107.0.0-2-cdfwm   0/1     Completed   0          34m
router-0                          2/2     Running     0          31m
routing-api-0                     2/2     Running     0          31m
secret-generation-2-cm95p         0/1     Completed   0          34m
secret-smuggler-2-jfrxd           0/1     Completed   0          34m
syslog-scheduler-0                2/2     Running     0          26m
tcp-router-0                      2/2     Running     0          31m
```

Check the Stratos console is working:

```console
$ kubectl -n stratos get pods
NAME                          READY   STATUS    RESTARTS   AGE
stratos-0                     3/3     Running   0          38m
stratos-db-5559d78699-x55cn   1/1     Running   0          39m
```

Point your browser at `https://stratos.$EIRINI_DOMAIN` and log in using `$EIRINI_ADMIN_PASSWORD`

```console
echo USERNAME=admin
echo PASSWORD=$EIRINI_ADMIN_PASSWORD
firefox https://stratos.$EIRINI_DOMAIN
```

## Deploy an Application

Once Cloud Foundry is up and running on Kubernetes we can deploy a test application.

Log into CF:

```console
$ cf login -a api.$EIRINI_DOMAIN -u admin -p $EIRINI_ADMIN_PASSWORD
API endpoint: api.app.gke.demo.paulczar.wtf
Authenticating...
OK
Targeted org system
API endpoint:   https://api.app.gke.demo.paulczar.wtf (API version: 2.142.0)
User:           admin
Org:            system
Space:          No space targeted, use 'cf target -s SPACE'
```

Create a space and target:

```console
cf create-space demo
cf target -s demo
```

Clone down and deploy an example application:

```console
git clone https://github.com/cloudfoundry-samples/cf-sample-app-spring
cd cf-sample-app-spring
cf push demo
```

Check the health of the app and get the URL:

```console
cf app demo
Showing health and status for app demo in org system / space demo as admin...

name:                demo
requested state:     started
isolation segment:   placeholder
routes:              demo-nice-kangaroo.app.gke.demo.paulczar.wtf
last uploaded:       Wed 23 Oct 14:30:06 CDT 2019
stack:               cflinuxfs3
buildpacks:          https://github.com/cloudfoundry/java-buildpack.git
```

Point your browser at the above URL and you should get a basic spring example application.