provider "argocd" {
  server_addr = "https://localhost:8080"
  username    = "admin"
  password    = "Df0CW8XpoObyNLzZ"
}

# Define Argo CD applications for Knative components

# Istio Application
resource "argocd_application" "istio_application" {
  metadata {
    name      = "istio-app"
    namespace = "argo"
  }

  spec {
    project = "default"

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "istio-system"  # Assuming Istio will be deployed in this namespace
    }

    source {
      repo_url        = "https://github.com/whoosh-labs/knative-infra"
      path            = "knative-istio"  # Path to Istio manifests in your repository
      target_revision = "main"  # Or specify the branch/tag you want to deploy
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
    }
  }
}

# Knative Serving Application
resource "argocd_application" "knative_serving_application" {
  metadata {
    name      = "knative-serving-app"
    namespace = "argo"
  }

  spec {
    project = "default"

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "knative-serving"  # Assuming Knative Serving will be deployed in this namespace
    }

    source {
      repo_url        = "https://github.com/whoosh-labs/knative-infra"
      path            = "knative"  # Path to Knative Serving manifests in your repository
      target_revision = "main"  # Or specify the branch/tag you want to deploy
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
    }
  }
}

# Knative Eventing Application
resource "argocd_application" "knative_eventing_application" {
  metadata {
    name      = "knative-eventing-app"
    namespace = "argo"
  }

  spec {
    project = "default"

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "knative-eventing"  # Assuming Knative Serving will be deployed in this namespace
    }

    source {
      repo_url        = "https://github.com/whoosh-labs/knative-infra"
      path            = "knative-eventing"  # Path to Knative Serving manifests in your repository
      target_revision = "main"  # Or specify the branch/tag you want to deploy
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
    }
  }
}


# Kafka Application
resource "argocd_application" "kafka_application" {
  metadata {
    name      = "kafka-app"
    namespace = "argo"
  }

  spec {
    project = "default"

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "kafka"  # Assuming Knative Serving will be deployed in this namespace
    }

    source {
      repo_url        = "https://github.com/whoosh-labs/knative-infra"
      path            = "knative-kafka"  # Path to Knative Serving manifests in your repository
      target_revision = "main"  # Or specify the branch/tag you want to deploy
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
    }
  }
}


