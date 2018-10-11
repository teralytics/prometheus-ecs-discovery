FROM golang:1.10
WORKDIR /go/src/github.com/teralytics/prometheus-ecs-discovery/
COPY main.go .
RUN go get .
RUN CGO_ENABLED=0 GOOS=linux go build -a -o prometheus-ecs-discovery .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=0 /go/src/github.com/teralytics/prometheus-ecs-discovery/prometheus-ecs-discovery .
CMD ["./prometheus-ecs-discovery"]
