ARG GO_VERSION=1.12

# Step 1: Install CA certificates and setup Go binary build
FROM golang:${GO_VERSION}-alpine AS build

# dummy GOPATH to allow go modules in WORKDIR
ENV GOPATH="/src/go"

RUN apk add --update --no-cache git gcc musl-dev ca-certificates

ARG USER_ID=700
ARG GROUP_ID=700

RUN addgroup -g $GROUP_ID -S service && adduser -u $USER_ID -D -G service service

COPY go.mod go.sum ./

RUN go mod download

COPY . ./

# disable the support for linking C code. This allows us to use the binary in scratch with no system libraries
ENV CGO_ENABLED=0
# compile linux only
ENV GOOS=linux

# Step 2: Build go binaries
FROM build as go-build

RUN go build -o /tmp/bin/ecs-discovery -a cmd/ecs-discovery/main.go

# Step 3: Copy binaries and ca-certificates to scratch (empty) image
FROM scratch

COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

COPY --from=go-build /tmp/bin /bin

USER service

ENV PATH="/bin"

ARG BUILD_DATE
ARG BUILD_NUMBER
ARG VCS_SHA

LABEL maintainer="reliability.engineering@ft.com" \
    com.ft.build-number="$BUILD_NUMBER" \
    org.opencontainers.authors="reliability.engineering@ft.com" \
    org.opencontainers.created="$BUILD_DATE" \
    org.opencontainers.licenses="MIT" \
    org.opencontainers.revision="$VCS_SHA" \
    org.opencontainers.title="prometheus-ecs-discovery" \
    org.opencontainers.source="https://github.com/Financial-Times/prometheus-ecs-discovery" \
    org.opencontainers.url="https://biz-ops.in.ft.com/System/prometheus-ecs-discovery" \
    org.opencontainers.vendor="financial-times"

CMD ["ecs-discovery"]
