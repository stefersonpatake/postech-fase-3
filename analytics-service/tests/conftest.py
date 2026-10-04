"""
O app.py cria os clientes boto3 e inicia o worker do SQS ao ser importado. Para
testes unitários (sem AWS), as variáveis de ambiente, o boto3 e a thread do worker
são substituídos antes do import.
"""
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

os.environ.setdefault("AWS_REGION", "us-east-1")
os.environ.setdefault("AWS_SQS_URL", "https://sqs.test/000000000000/fila")
os.environ.setdefault("AWS_DYNAMODB_TABLE", "TabelaDeTeste")

with patch("boto3.Session", MagicMock()), patch("threading.Thread", MagicMock()):
    import app as service  # noqa: E402


@pytest.fixture
def client():
    service.app.config["TESTING"] = True
    return service.app.test_client()


@pytest.fixture
def aws():
    """ Clientes SQS e DynamoDB simulados, zerados a cada teste. """
    service.sqs_client.reset_mock()
    service.dynamodb_client.reset_mock(side_effect=True)
    return service
