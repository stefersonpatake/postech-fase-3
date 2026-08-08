-- postgres-flags hospeda 2 databases: 'flagapi' (criado via POSTGRES_DB) e
-- 'targeting_db' (criado aqui). Cada serviço aplica seu próprio schema
-- (db/init.sql) via entrypoint.sh na primeira vez que sobe.
CREATE DATABASE targeting_db;
