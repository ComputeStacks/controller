# Order Flow

Documenting flow of models, workers, and services used when an order event is triggered.

## New Order
* Deployments::OrderController
  - BuildOrderService
    + ProcessOrderWorker
      * ProcessOrderService
        - NetworkServices::GenerateProjectNetworkService
          - NetworkServices::CreateBridgeNetworkService
        - OrderServices::ContainerServiceOrderService
          + ProvisionServices::ContainerServiceProvisioner
        - ProvisionServices::SftpProvisioner
        - DeployServices::DeployProjectService
          + NetworkWorkers::ProjectPolicyWorker
          + PowerCycleContainerService
          + LoadBalancerServices::DeployConfigService
          + ProjectServices::StoreMetadata

## Resize Service
* ContainerServiceWorkers::ResizeServiceWorker
  - ProvisionServices::ContainerResizeProvisioner
  - ProjectServices::StoreMetadata

## Scale Service
* ContainerServiceWorkers::ScaleServiceWorker
  - ProvisionServices::ScaleServiceProvisioner
    + ProvisionServices::ContainerProvisioner
    + ContainerWorkers::ProvisionWorker
    + ContainerServices::TrashContainer
    + ProjectServices::StoreMetadata

## Delete ContainerService
* ContainerServiceWorkers::TrashServiceWorker
  - ContainerServices::TrashService
  - ProjectWorkers::SftpInitWorker
  - ProjectServices::StoreMetadata
