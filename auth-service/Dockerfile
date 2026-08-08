FROM golang:1.21-alpine AS builder

WORKDIR /src

COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 go build -o /out/auth-service .

FROM alpine:3.19

RUN apk add --no-cache postgresql-client

WORKDIR /app

COPY --from=builder /out/auth-service .
COPY db/ ./db/
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

EXPOSE 8001

ENTRYPOINT ["sh", "./entrypoint.sh"]
