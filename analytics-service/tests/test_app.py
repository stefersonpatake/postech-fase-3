import json

from botocore.exceptions import ClientError


def make_message(body):
    return {"MessageId": "msg-1", "ReceiptHandle": "recibo-1", "Body": body}


EVENT = {
    "user_id": "user-123",
    "flag_name": "nova-tela",
    "result": True,
    "timestamp": "2026-01-01T00:00:00Z",
}


def test_health(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_process_message_saves_event_and_deletes_message(aws):
    aws.process_message(make_message(json.dumps(EVENT)))

    aws.dynamodb_client.put_item.assert_called_once()
    kwargs = aws.dynamodb_client.put_item.call_args.kwargs
    assert kwargs["TableName"] == "TabelaDeTeste"
    assert kwargs["Item"]["user_id"] == {"S": "user-123"}
    assert kwargs["Item"]["flag_name"] == {"S": "nova-tela"}
    assert kwargs["Item"]["result"] == {"BOOL": True}
    assert kwargs["Item"]["event_id"]["S"]

    aws.sqs_client.delete_message.assert_called_once_with(
        QueueUrl="https://sqs.test/000000000000/fila", ReceiptHandle="recibo-1"
    )


def test_process_message_keeps_invalid_json_in_queue(aws):
    aws.process_message(make_message("isto não é JSON"))

    aws.dynamodb_client.put_item.assert_not_called()
    aws.sqs_client.delete_message.assert_not_called()


def test_process_message_keeps_message_when_dynamodb_fails(aws):
    aws.dynamodb_client.put_item.side_effect = ClientError(
        {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "limite"}}, "PutItem"
    )

    aws.process_message(make_message(json.dumps(EVENT)))

    aws.sqs_client.delete_message.assert_not_called()
