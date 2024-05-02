provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_manifest" "knative_eventing" {
  manifest = file("knative-eventing/eventing-core.yaml")
}

resource "kubernetes_manifest" "knative_eventing_crds" {
  manifest = file("/knative-eventing/eventing-crds.yaml")
}
