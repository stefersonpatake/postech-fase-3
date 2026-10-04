# Fila de eventos: evaluation-service publica, analytics-service consome.
module "sqs" {
  source = "../modules/sqs"

  name = "${var.project}-events"
}
