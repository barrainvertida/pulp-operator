FROM golang:1.18 as builder

WORKDIR /usr/src/app

# pre-copy/cache go.mod for pre-downloading dependencies and only redownloading them in subsequent builds if they change
COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY . .
RUN go build -v -o check_resources ./...

FROM alpine
COPY --from=builder /usr/src/app/check_resources /bin/

CMD ["check_resources"]
