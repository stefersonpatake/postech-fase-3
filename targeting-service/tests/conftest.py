"""
O app.py abre o pool de conexões com o PostgreSQL ao ser importado. Para testes
unitários (sem banco), as variáveis de ambiente e o pool são substituídos antes
do import.
"""
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

os.environ.setdefault("DATABASE_URL", "host=localhost dbname=test user=test password=test")
os.environ.setdefault("AUTH_SERVICE_URL", "http://auth-service.test")

with patch("psycopg2.pool.SimpleConnectionPool", MagicMock()):
    import app as service  # noqa: E402


@pytest.fixture
def client():
    service.app.config["TESTING"] = True
    return service.app.test_client()


@pytest.fixture
def auth_ok():
    """ Simula o auth-service aceitando a chave de API. """
    with patch.object(service.requests, "get", return_value=MagicMock(status_code=200)) as mocked:
        yield mocked


@pytest.fixture
def auth_denied():
    """ Simula o auth-service rejeitando a chave de API. """
    with patch.object(service.requests, "get", return_value=MagicMock(status_code=401)) as mocked:
        yield mocked
