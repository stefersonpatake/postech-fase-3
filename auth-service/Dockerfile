FROM golang:1.25-alpine AS builder

WORKDIR /src

# Dependências primeiro: a camada fica em cache enquanto go.mod/go.sum não mudarem.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o /out/auth-service .

FROM alpine:3.22

# Aplica as correções de segurança publicadas depois da imagem base.
RUN apk upgrade --no-cache

RUN apk add --no-cache postgresql-client

WORKDIR /app

COPY --from=builder /out/auth-service .
COPY db/ ./db/
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

EXPOSE 8001

ENTRYPOINT ["sh", "./entrypoint.sh"]
