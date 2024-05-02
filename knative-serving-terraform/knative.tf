provider "kubernetes" {
  config_path = "~/.kube/config"
}


resource "kubernetes_manifest" "knative_serving" {
  manifest = file("knative/serving-core.yaml")
}

resource "kubernetes_manifest" "knative_serving_crds" {
  manifest = file("/knative/serving-crds.yaml")
}

