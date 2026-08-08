#!/bin/sh
set -e

# O que este script faz:
# 1. Checa as variáveis de ambiente para o banco de dados.
# 2. Entra em um loop que tenta se conectar ao banco de dados.
# 3. Só sai do loop quando o banco de dados está pronto para aceitar conexões.
# 4. Aplica o schema (db/init.sql), que é idempotente (CREATE TABLE IF NOT EXISTS).
# 5. Inicia o binário do serviço (main.go não tem retry de conexão próprio).

if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
  echo "Erro: DB_HOST, DB_PORT, DB_USER e DB_NAME devem ser definidos."
  exit 1
fi

echo "Aguardando o banco de dados em ${DB_HOST}:${DB_PORT}..."
while ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -q; do
  echo "Banco de dados indisponível - aguardando..."
  sleep 1
done
echo "Banco de dados disponível!"

echo "Aplicando schema (db/init.sql)..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f db/init.sql

echo "Iniciando o auth-service na porta ${PORT:-8001}..."
exec ./auth-service
