FROM golang:1.25-alpine AS builder

WORKDIR /src

# Dependências primeiro: a camada fica em cache enquanto go.mod/go.sum não mudarem.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o /out/evaluation-service .

FROM alpine:3.22

# Aplica as correções de segurança publicadas depois da imagem base.
RUN apk upgrade --no-cache

WORKDIR /app

COPY --from=builder /out/evaluation-service .

# Processo sem privilégios de root dentro do container.
RUN adduser -D -u 10001 app
USER app

EXPOSE 8004

CMD ["./evaluation-service"]
