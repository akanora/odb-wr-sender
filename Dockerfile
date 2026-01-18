FROM golang:1.25.6-alpine3.23 AS builder

RUN apk add --no-cache git

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o ./build/app ./cmd/app

FROM alpine:3.23

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/build/app .
COPY --from=builder /app/config ./config

EXPOSE 4175

CMD ["./app", "-config", "config/app.toml"]
