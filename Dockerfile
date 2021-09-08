FROM golang:1.15-alpine
WORKDIR /src
RUN apk --no-cache add \
      git \
      ca-certificates
COPY *.go go.mod go.sum ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/prometheus-ecs-discovery .

FROM scratch
COPY --from=0 /bin/prometheus-ecs-discovery /bin/
COPY --from=0 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ENTRYPOINT ["prometheus-ecs-discovery"]
