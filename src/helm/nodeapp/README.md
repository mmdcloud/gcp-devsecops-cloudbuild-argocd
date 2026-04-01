# Helm Chart for NodeApp

This Helm chart deploys the NodeApp application on a Kubernetes cluster. It includes the necessary Kubernetes manifests for deployment, service, and ingress.

## Prerequisites

- Kubernetes 1.12+
- Helm 3.x

## Installation

To install the chart, use the following command:

```bash
helm install <release-name> ./nodeapp
```

Replace `<release-name>` with your desired release name.

## Configuration

The following table lists the configurable parameters of the NodeApp chart and their default values:

| Parameter                | Description                                   | Default           |
|--------------------------|-----------------------------------------------|-------------------|
| `replicaCount`           | Number of replicas for the deployment        | `1`               |
| `image.repository`       | Container image repository                    | `your-image-repo` |
| `image.tag`              | Container image tag                           | `latest`          |
| `service.type`           | Service type (ClusterIP, NodePort, LoadBalancer) | `ClusterIP`       |
| `service.port`           | Service port                                  | `80`              |
| `ingress.enabled`        | Enable ingress resource                       | `false`           |
| `ingress.hosts`          | Ingress hostnames                             | `[]`              |
| `env`                    | Environment variables for the application     | `{}`              |

## Usage

To customize the deployment, create a `values.yaml` file with your desired configurations and install the chart using:

```bash
helm install <release-name> ./nodeapp -f values.yaml
```

## Uninstallation

To uninstall the chart, use the following command:

```bash
helm uninstall <release-name>
```

## Notes

- Ensure that your Kubernetes cluster has the necessary resources to run the application.
- For more advanced configurations, refer to the official Helm documentation.