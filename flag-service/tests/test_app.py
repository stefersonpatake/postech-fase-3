import requests

HEADERS = {"Authorization": "Bearer tm_key_teste"}


def test_health(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_requires_authorization_header(client):
    response = client.get("/flags")

    assert response.status_code == 401
    assert "Authorization" in response.get_json()["error"]


def test_rejects_invalid_api_key(client, auth_denied):
    response = client.get("/flags", headers=HEADERS)

    assert response.status_code == 401
    auth_denied.assert_called_once()
    assert auth_denied.call_args.args[0].endswith("/validate")


def test_auth_service_timeout_returns_504(client, auth_ok):
    auth_ok.side_effect = requests.exceptions.Timeout()

    response = client.get("/flags", headers=HEADERS)

    assert response.status_code == 504


def test_auth_service_unavailable_returns_503(client, auth_ok):
    auth_ok.side_effect = requests.exceptions.ConnectionError()

    response = client.get("/flags", headers=HEADERS)

    assert response.status_code == 503


def test_create_validates_required_fields(client, auth_ok):
    response = client.post("/flags", json={"description": "sem nome"}, headers=HEADERS)

    assert response.status_code == 400
