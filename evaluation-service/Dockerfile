FROM golang:1.21-alpine AS builder

WORKDIR /src

COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 go build -o /out/evaluation-service .

FROM alpine:3.19

WORKDIR /app

COPY --from=builder /out/evaluation-service .

EXPOSE 8004

CMD ["./evaluation-service"]
