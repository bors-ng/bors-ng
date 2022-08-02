locals {
  # Kubernetes matching labels expressions are used by the ReplicaControllers to find the PODs
  # that belongs to them and assert if they are up to date and Running
  # This set of labels are not allowed to change when a rolling upgrade happens so they have to remain
  # unchanged for the life of Deployment
  #
  # immutable
  bors_match_labels = {
    "app.kubernetes.io/name"       = "bors"
    "app.kubernetes.io/component"  = "application"
    "app.kubernetes.io/part-of"    = "bors"
    "app.kubernetes.io/managed-by" = "Terraform"
  }

  # The Deployment, POD, Service... related K8s resources with Bors use this group of labels so they are consistent
  #
  # A requirement between the Deployment.spec.selector.match_labels and POD.metadata.labels
  # is that the POD has to contain the same as the match_labels but it could also be a superset of them
  # and include more details about the application
  bors_labels = merge(
    local.bors_match_labels,
    {
      "app.kubernetes.io/version" = "2021-03-23"
  })

  bors_port            = 4000
  bors_public_port     = 443
  bors_public_protocol = "https"
  bors_hostname        = "bors.${local.cluster_domain}"

  bors_env_vars = {
    "PORT"                  = local.bors_port
    "PUBLIC_PORT"           = "${local.bors_public_port}",
    "PUBLIC_PROTOCOL"       = "${local.bors_public_protocol}",
    "PUBLIC_HOST"           = local.bors_hostname,
    "DATABASE_USE_SSL"      = "false",
    "DATABASE_AUTO_MIGRATE" = "true",
    "COMMAND_TRIGGER"       = "bors",
  }

  # docker pull borsng/bors-ng:latest
  # docker images --digests borsng/bors-ng:latest
  # Remember to update teh version label ("app.kubernetes.io/version") above with the data
  # from the sha (below) from the docker image tag "latest" the only one published by bors
  bors_image_256sha = "sha256:56ce5c32d794de7e993a2c90411daa071f50a162e39de1e4001165810194430e"

  bors_db = {
    hostname = "db"
    port = 5432
    username = "user"
    password = "pssw"
  }
  bors_github = {
    client_id = ""
    client_id_secret = ""
    integration_id = ""
    integration_pem_b64 = base64encode("")
    webhook_secret = ""
  }

  ingress_class = ""
}

resource random_password bors_cookie_salt {
  length  = 64
  special = false
}

resource kubernetes_namespace bors {
  metadata {
    name   = "bors"
    labels = local.bors_labels
  }
}

resource kubernetes_secret bors {
  metadata {
    name      = "bors"
    namespace = kubernetes_namespace.bors.metadata.0.name
    labels    = local.bors_labels
  }
  data = {
    // ecto://postgres:postgres@localhost/ecto_simple
    "DATABASE_URL"           = "ecto://${local.bors_db.username}:${urlencode(local.bors_db.password)}@${local.bors_db.hostname}:${local.bors_db.port}/bors_ng"
    "SECRET_KEY_BASE"        = random_password.bors_cookie_salt.result,
    "GITHUB_CLIENT_ID"       = local.bors_github.client_id
    "GITHUB_CLIENT_SECRET"   = local.bors_github.client_id_secret
    "GITHUB_INTEGRATION_ID"  = local.bors_github.integration_id
    "GITHUB_INTEGRATION_PEM" = local.bors_github.integration_pem_b64
    "GITHUB_WEBHOOK_SECRET"  = local.bors_github.webhook_secret
  }
}

resource kubernetes_deployment bors {
  metadata {
    name      = "bors"
    namespace = kubernetes_namespace.bors.metadata.0.name
    labels    = local.bors_labels
  }

  spec {
    # Bors does not support clustering
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = local.bors_match_labels
    }

    template {
      metadata {
        labels = local.bors_labels
        annotations = {
          "kubernetes.secret.hash/${kubernetes_secret.bors.metadata.0.name}" = base64encode(join("", values(kubernetes_secret.bors.data)))
        }
      }

      spec {
        container {
          image             = "borsng/bors-ng@${local.bors_image_256sha}"
          image_pull_policy = "IfNotPresent"
          name              = "bors"

          resources {
            limits {
              cpu    = "1"
              memory = "1Gi"
            }
            requests {
              cpu    = "1"
              memory = "1Gi"
            }
          }

          port {
            name           = "http"
            container_port = local.bors_port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.bors.metadata.0.name
            }
          }

          dynamic "env" {
            for_each = local.bors_env_vars
            content {
              name  = env.key
              value = env.value
            }
          }
        }
      }
    }
  }
}

resource kubernetes_service bors {
  metadata {
    name      = "bors"
    namespace = kubernetes_namespace.bors.metadata.0.name
    labels    = local.bors_labels
  }

  spec {
    selector = local.bors_match_labels
    port {
      name        = "http"
      port        = 8080
      target_port = "http"
    }
  }
}

resource kubernetes_ingress bors {
  metadata {
    name      = "bors"
    namespace = kubernetes_namespace.bors.metadata.0.name
    labels    = local.bors_labels
    annotations = {
      "kubernetes.io/ingress.class" = local.ingress_class
    }
  }

  spec {
    rule {
      host = local.bors_hostname
      http {
        path {
          backend {
            service_name = kubernetes_service.bors.metadata.0.name
            service_port = "http"
          }
          path = "/"
        }
      }
    }
  }
}
