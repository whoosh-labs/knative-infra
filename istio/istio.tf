provider "kubernetes" {
  config_path = "~/.kube/config"
}

#istio
resource "kubernetes_manifest" "knative_istio" {
  manifest = file("/knative-istio/istio.yaml")
}

resource "kubernetes_manifest" "knative_istio_net" {
  manifest = file("/knative-istio/net-istio.yaml")
}
