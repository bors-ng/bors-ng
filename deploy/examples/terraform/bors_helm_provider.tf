locals {
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

resource kubernetes_namespace bors {
  metadata {
    name   = "bors"
  }
}

resource kubernetes_secret bors {
  metadata {
    name      = "bors"
    namespace = kubernetes_namespace.bors.metadata.0.name
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

resource helm_release bors {
  name       = "bors"
  repository = "<repository>"
  chart      = "bors-ng"
  version    = "0.1.0"
  namespace  = kubernetes_namespace.bors.metadata.0.name

  values = [
    <<VALUES
envFrom:
  - secretRef:
      name: "${kubernetes_secret.bors.metadata.0.name}"
      optional: false
postgresql:
  enabled: false
VALUES
  ]
}
