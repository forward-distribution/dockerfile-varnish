# Varnish

The Varnish setup we at Netcetera currently use for the delivery when paywall from MPP is needed. Such paywall are used in the BLZ and ASC websites.

### Build

```bash
colima start
docker build -t forwardpublishing/varnish-paywall .
```

If you have trouble with the command (usually becuase of using Apple Silicon) see the next section. Trouble manifests such as:
- failing builds with no obvious reason
- core dumps during build

### Build (Apple Silicon)

Since we're building linux/amd64 images on Apple Silicon (arm64 architecture) we need to take more steps before building:
```bash
# ensure latest docker version
brew install docker

# install buildx (since we don't use docker desktop, this must be installed separately)
brew install docker-buildx

# and link it so docker can use it
mkdir ~/.docker/cli-plugins
ls ~/.docker/cli-plugins
ln -sfn $(which docker-buildx) ~/.docker/cli-plugins/docker-buildx

# confirm it installed properly -- should recognize as valid docker command
docker buildx
# OK:  Extended build capabilities with BuildKit
# NOK: docker: 'buildx' is not a docker command.

# setup AMD and ARM colima instances (ARM not required since we can run amd64 images locally via rosetta, but recommended)
# source - https://github.com/abiosoft/colima/issues/44#issuecomment-952281801
# this creates 'colima-amd'
colima start --profile amd --arch amd
# this creates 'colima-arm'
colima start --profile arm --arch arm

# then setup docker to use these colima instances for building (again multiarch recommended, but not needed)
# named 'custom-colima-issues-44' after the source
docker buildx create --use --name custom-colima-issues-44 colima-amd
docker buildx create --append --name custom-colima-issues-44 colima-arm

docker buildx use custom-colima-issues-44
```

Then to build:
```bash
# I had a lot of issues where (run build) - OK | (run build) - FAIL
# Pruning the build cache solved this
docker buildx prune

# Finally to build an image - add/remove/change the image name, tag and platforms as needed
docker buildx build --no-cache --platform linux/amd64,linux/arm64 .
docker buildx build --no-cache --platform=linux/amd64 .
```

Building and publishing is done in one step:
```bash
docker login
docker buildx build --platform=linux/amd64,linux/arm64 --push -t forwardpublishing/<image-name>:<version> .
```
TODO: GAT: 05.04.2025 Update the CircleCI build process, looks like it's disabled; last 10-20 prod images were built locally.

Local testing:
```bash
docker login
docker buildx build --platform=linux/amd64 --load -t forwardpublishing/<image-name>:<version> .
docker run -ti --platform linux/amd64 forwardpublishing/<image-name>:<version>
```

To test for vulnerabilities use `trivy`:
```bash
brew install trivy

# find the context where the image was built
docker context ls
# NAME         DESCRIPTION                               DOCKER ENDPOINT                                      ERROR
# colima-arm *   colima [profile=arm]                      unix:///Users/glatanas/.colima/arm/docker.sock       

# and use it (otherwise trivy can't find the image)
DOCKER_HOST="unix://$HOME/.colima/arm/docker.sock" trivy image <image-name:tag>
```

### Upgrading LD Docker versions

Livingdocs explicitly told us they're NOT commiting to maintaining older Varnish images. (here - https://publishingsuite.slack.com/archives/C01V67WDRC2/p1737383847907879)
For part of our newspapers we must still use Varnish 6 for curl and we haven't migrated to a newer version yet.
Therefore sometimes we must do it by ourselves.

(!) To be updated when we switch to a new varnish repo. In the meantime: (!)

Below I've outlined the procedure for building 6.5.2-r1. It's quite specific, but take what you can from it until we provide more detailed instructions.

1. `git clone https://github.com/livingdocsIO/dockerfile-varnish.git`

2. `git checkout 65301a2b5f2f # the branch with 6.5.1, last version which works with libvmod-curl`

3. Apply the following changes to their Dockerfile
```
-FROM golang:1.13.10-alpine3.11 as go
+FROM golang:1.23.5-alpine3.21 AS go

-RUN go get -d github.com/jonnenauha/prometheus_varnish_exporter github.com/kelseyhightower/confd
-RUN cd /go/src/github.com/jonnenauha/prometheus_varnish_exporter && git checkout 1.5.2 && go build -ldflags "-X 'main.Version=1.5.2' -X 'main.VersionHash=$(git rev-parse --short HEAD)' -X 'main.VersionDate=$(date -u '+%d.%m.%Y %H:%M:%S')'" -o /go/bin/prometheus_varnish_exporter
-RUN cd /go/src/github.com/kelseyhightower/confd && git checkout v0.15.0 && go build -ldflags "-X 'main.GitSHA=$(git rev-parse --short HEAD)'" -o /go/bin/confd
+RUN git clone https://github.com/jonnenauha/prometheus_varnish_exporter.git
+RUN cd prometheus_varnish_exporter && git checkout 1.6 && go build -ldflags "-X 'main.Version=1.6' -X 'main.VersionHash=$(git rev-parse --short HEAD)' -X 'main.VersionDate=$(date -u '+%d.%m.%Y %H:%M:%S')'" -o /go/bin/prometheus_varnish_exporter
+RUN git clone https://github.com/kelseyhightower/confd.git
+RUN cd confd && git checkout 919444e && go build -ldflags "-X 'main.GitSHA=$(git rev-parse --short HEAD)'" -o /go/bin/confd
 
-FROM alpine
-ENV VARNISH_VERSION=6.5.1-r0
+FROM alpine:3.13
+ENV VARNISH_VERSION=6.5.2-r1
```

4. Build as described above. In my case I ran:
`docker buildx build --no-cache --platform=linux/amd64 --push -t forwardpublishing/ld-fp-upgraded-varnish:6.5.2-r1 .`

### Run

```
docker run --rm -it -e BACKEND=example.com:80 -p 8080:80 -p 6081:6081 --name varnish forwardpublishing/varnish-paywall

# test
curl -H 'Host: example.com' localhost:8080
```

### Deploy

Each "merge to master" creates a docker image that you can use afterwards to deploy to a specific environment.

## Configuration options

All configuration is done using environment variables.

### Varnish Daemon Options
* `VARNISH_PORT`, optional, default: 80
* `VARNISH_ADMIN_PORT`, optional, default: 2000
* `VARNISH_ADMIN_SECRET_FILE`, optional, default: `VARNISH_ADMIN_SECRET` env variable
* `VARNISH_ADMIN_SECRET`, optional, default to a random string
* `VARNISH_CACHE_SIZE`, optional, default: 512m
* `VARNISH_CACHE_TTL`, optional, default: 4m
* `VARNISH_CACHE_GRACE`, optional, default: 24h
* `VARNISH_CACHE_KEEP`, optional, default: 1h
* `VARNISH_RUNTIME_PARAMETERS`, optional
* `VARNISH_ACCESS_LOG`, optional, default: true, log frontend requests

### Varnish Backend Options
* `BACKEND` the hostname:port of the backend, supports comma delimited values
* `BACKEND_MAX_CONNECTIONS`, optional, default: 75
* `BACKEND_FIRST_BYTES_TIMEOUT`, optional, default: 10s
* `BACKEND_BETWEEN_BYTES_TIMEOUT`, optional, default: 5s
* `BACKEND_CONNECT_TIMEOUT`, optional, default: 5s
* `BACKEND_PROBE`, optional, default: false
* `BACKEND_PROBE_URL`, optional, default: /status
* `BACKEND_PROBE_INTERVAL`, optional, default: 1s
* `BACKEND_PROBE_TIMEOUT`, optional, default: 1s
* `BACKEND_PROBE_WINDOW`, optional, default: 3
* `BACKEND_PROBE_THRESHOLD`, optional, default: 2
* `REMOTE_BACKEND`, optional, the host:port of additional backends you can use for example with ESI

### Varnish EMeter required values
* `E_METER_URL` eMeter endpoint used for sending eSuiteInformation
* `E_METER_X_TOKEN`, eMeter unique x-token-id

### VCL Configuration Options
* `ERROR_PAGE`, optional, an html page that is shown for every 5xx error instead of the regular server response. You can set it to something like `/error` or `http://some-error-page/error?code={{code}}`
  - Attention, https doesn't work
  - Use a `{{code}}` placeholder, which will be replaced with the error code.
* `PURGE_IP_WHITELIST`: a list of ip addresses that are allowed to purge pages. by default we've whitelisted the private networks.
* `VARNISH_STRIP_QUERYSTRING`: Forces varnish to remove all the query strings from a url before it gets sent to a backend, default: false
* `HOSTNAME` and `HOSTNAME_PREFIX`: By default we set a `x-served-by` header on the response of a request in varnish. Because the hostname is automatically set in docker, we've added a prefix, to make it more customizable.
* `VARNISH_CUSTOM_SCRIPT`: Allows us to inject some script at the end of the `vcl_recv` function.


### Prometheus exporter Options
* `PROMETHEUS_EXPORTER_PORT`, optional, default 9131
