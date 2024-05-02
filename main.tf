provider "kubernetes" {
  config_path = "~/.kube/config"
}


resource "kubernetes_manifest" "knative_serving" {
  manifest = file("knative/serving-core.yaml")
}

resource "kubernetes_manifest" "knative_serving_crds" {
  manifest = file("/knative/serving-crds.yaml")
}

resource "kubernetes_manifest" "knative_eventing" {
  manifest = file("knative-eventing/eventing-core.yaml")
}

resource "kubernetes_manifest" "knative_eventing_crds" {
  manifest = file("/knative-eventing/eventing-crds.yaml")
}

resource "kubernetes_manifest" "knative_istio" {
  manifest = file("/knative-istio/istio.yaml")
}

resource "kubernetes_manifest" "knative_istio_net" {
  manifest = file("/knative-istio/net-istio.yaml")
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
