provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_manifest" "knative_kafka_broker" {
  manifest = file("/knative-kafka/eventing-kafka-broker.yaml")
}

resource "kubernetes_manifest" "knative_kafka_controller" {
  manifest = file("/knative-kafka/eventing-kafka-controller.yaml")
}

resource "kubernetes_manifest" "knative_kafka_source" {
  manifest = file("/knative-kafka/eventing-kafka-source.yaml")
}
