# ------------------------------------------------------------------------
# ArgoCD Namespace
# ------------------------------------------------------------------------
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [
    google_container_node_pool.system,
    google_container_node_pool.apps
  ]
}

# ------------------------------------------------------------------------
# ArgoCD — installed via Helm
# Docs: https://argoproj.github.io/argo-helm
# ------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set = [
    # ── HA mode: run 2 replicas of server + repo-server ──────────────────
    {
      name  = "server.replicas"
      value = "2"
    },
    {
      name  = "repoServer.replicas"
      value = "2"
    },
    {
      name  = "applicationSet.replicas"
      value = "2"
    },

    # ── Expose via internal LoadBalancer (swap to Ingress if you have one) ─
    {
      name  = "server.service.type"
      value = "ClusterIP"
    },

    # ── Disable insecure flag — TLS terminated at the LB/ingress layer ───
    {
      name  = "server.extraArgs[0]"
      value = "--insecure"   # remove this line if terminating TLS in-pod
    },

    # ── Resource limits: server ───────────────────────────────────────────
    {
      name  = "server.resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "server.resources.limits.memory"
      value = "512Mi"
    },
    {
      name  = "server.resources.requests.cpu"
      value = "100m"
    },
    {
      name  = "server.resources.requests.memory"
      value = "256Mi"
    },

    # ── Resource limits: repo-server ──────────────────────────────────────
    {
      name  = "repoServer.resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "repoServer.resources.limits.memory"
      value = "512Mi"
    },
    {
      name  = "repoServer.resources.requests.cpu"
      value = "100m"
    },
    {
      name  = "repoServer.resources.requests.memory"
      value = "256Mi"
    },

    # ── Resource limits: application-controller ───────────────────────────
    {
      name  = "controller.resources.limits.cpu"
      value = "1000m"
    },
    {
      name  = "controller.resources.limits.memory"
      value = "1Gi"
    },
    {
      name  = "controller.resources.requests.cpu"
      value = "250m"
    },
    {
      name  = "controller.resources.requests.memory"
      value = "512Mi"
    },

    # ── Schedule ArgoCD itself on the system node pool ────────────────────
    {
      name  = "server.tolerations[0].key"
      value = "node-role"
    },
    {
      name  = "server.tolerations[0].value"
      value = "system"
    },
    {
      name  = "server.tolerations[0].effect"
      value = "NoSchedule"
    },
    {
      name  = "repoServer.tolerations[0].key"
      value = "node-role"
    },
    {
      name  = "repoServer.tolerations[0].value"
      value = "system"
    },
    {
      name  = "repoServer.tolerations[0].effect"
      value = "NoSchedule"
    },
    {
      name  = "controller.tolerations[0].key"
      value = "node-role"
    },
    {
      name  = "controller.tolerations[0].value"
      value = "system"
    },
    {
      name  = "controller.tolerations[0].effect"
      value = "NoSchedule"
    },

    # ── Redis (bundled) ───────────────────────────────────────────────────
    {
      name  = "redis.resources.limits.cpu"
      value = "200m"
    },
    {
      name  = "redis.resources.limits.memory"
      value = "256Mi"
    },
    {
      name  = "redis.resources.requests.cpu"
      value = "50m"
    },
    {
      name  = "redis.resources.requests.memory"
      value = "128Mi"
    },

    # ── Metrics for Prometheus scraping ───────────────────────────────────
    {
      name  = "server.metrics.enabled"
      value = "true"
    },
    {
      name  = "repoServer.metrics.enabled"
      value = "true"
    },
    {
      name  = "controller.metrics.enabled"
      value = "true"
    },
  ]

  wait          = true
  wait_for_jobs = true
  timeout       = 600   # ArgoCD CRDs + webhook jobs take longer than Crossplane

  depends_on = [kubernetes_namespace.argocd]
}

# Wait for ArgoCD CRDs (Application, AppProject, etc.) to be established
resource "time_sleep" "wait_for_argocd" {
  depends_on      = [helm_release.argocd]
  create_duration = "60s"
}

# ------------------------------------------------------------------------
# ArgoCD default AppProject
# Keeps the null_resource/kubectl pattern so there is no plan-time API
# server connection (same reason as your Crossplane providers above).
# ------------------------------------------------------------------------
resource "null_resource" "argocd_default_app_project" {
  count = var.install_argocd_app_project ? 1 : 0

  triggers = {
    cluster_id    = google_container_cluster.primary.id
    project_name  = var.argocd_project_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = local.kubectl_env
    command     = <<-EOT
      ${local.gcloud_auth}
      kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: ${var.argocd_project_name}
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: "Default platform project"
  sourceRepos:
    - '*'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
EOF
    EOT
  }

  depends_on = [time_sleep.wait_for_argocd]
}

# ------------------------------------------------------------------------
# ArgoCD Image Updater (optional)
# Polls container registries and opens PRs / commits tag bumps
# Docs: https://argocd-image-updater.readthedocs.io
# ------------------------------------------------------------------------
resource "helm_release" "argocd_image_updater" {
  count = var.install_argocd_image_updater ? 1 : 0

  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  version    = var.argocd_image_updater_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set = [
    {
      name  = "config.argocd.serverAddress"
      value = "argocd-server.${var.argocd_namespace}.svc.cluster.local"
    },
    {
      name  = "config.argocd.insecure"
      value = "true"
    },
    {
      name  = "resources.limits.cpu"
      value = "200m"
    },
    {
      name  = "resources.limits.memory"
      value = "256Mi"
    },
    {
      name  = "resources.requests.cpu"
      value = "50m"
    },
    {
      name  = "resources.requests.memory"
      value = "128Mi"
    },
    {
      name  = "tolerations[0].key"
      value = "node-role"
    },
    {
      name  = "tolerations[0].value"
      value = "system"
    },
    {
      name  = "tolerations[0].effect"
      value = "NoSchedule"
    },
  ]

  wait    = true
  timeout = 300

  depends_on = [time_sleep.wait_for_argocd]
}

# ------------------------------------------------------------------------
# ArgoCD Notifications Controller (optional)
# Sends Slack / PagerDuty / email alerts on sync events
# Bundled in argo-cd chart >=5.x; kept separate here for explicit control
# ------------------------------------------------------------------------
resource "null_resource" "argocd_notifications_secret" {
  count = var.install_argocd_notifications ? 1 : 0

  triggers = {
    cluster_id = google_container_cluster.primary.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = local.kubectl_env
    command     = <<-EOT
      ${local.gcloud_auth}
      kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: ${var.argocd_namespace}
type: Opaque
stringData:
  slack-token: "${var.argocd_slack_token}"
EOF
    EOT
  }

  depends_on = [time_sleep.wait_for_argocd]
}

resource "null_resource" "argocd_notifications_configmap" {
  count = var.install_argocd_notifications ? 1 : 0

  triggers = {
    cluster_id = google_container_cluster.primary.id
    slack_channel = var.argocd_slack_channel
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = local.kubectl_env
    command     = <<-EOT
      ${local.gcloud_auth}
      kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: ${var.argocd_namespace}
data:
  service.slack: |
    token: $slack-token
  template.app-sync-succeeded: |
    message: |
      Application {{.app.metadata.name}} sync succeeded.
  template.app-sync-failed: |
    message: |
      Application {{.app.metadata.name}} sync FAILED. Error: {{.app.status.operationState.message}}
  trigger.on-sync-succeeded: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-sync-succeeded]
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]
  defaultTriggers: |
    - on-sync-failed
EOF
    EOT
  }

  depends_on = [null_resource.argocd_notifications_secret]
}