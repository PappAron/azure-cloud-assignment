# Cloud Infrastructure Documentation

## Architecture Overview
The infrastructure is provisioned using **Terraform** and hosted on **Azure Kubernetes Service (AKS)**. This setup prioritizes scalability, modularity, and automated lifecycle management.



### Core Components

| Component | Technology | Description |
| :--- | :--- | :--- |
| **Compute** | Azure AKS | A managed Kubernetes cluster for container orchestration. |
| **Registry** | Azure ACR | Private registry for storing and versioning Docker images. |
| **Database** | Azure Cache for Redis | A managed DBaaS used for high-availability session storage. |
| **IaC** | Terraform | Used to define the "hardware" (AKS, Redis, ACR, VNet). |
| **Orchestration** | Helm | Used for packaging and deploying monitoring and custom apps. |

---

## Design Justifications

### 1. Why Kubernetes (AKS)?
Kubernetes was selected over traditional VMs or standard PaaS (like Azure App Service) for several key reasons:
* **Microservices Management:** The application consists of **11+ polyglot microservices**, which require a robust ecosystem for management.
* **Service Discovery:** Native internal networking simplifies communication between services.
* **Resilience:** AKS provides the necessary **auto-scaling** and **self-healing** capabilities required for a distributed system of this scale.

### 2. Why Managed Redis (DBaaS)?
Rather than running Redis as a pod inside the cluster, we utilize **Azure Cache for Redis**. 
> **Key Benefit:** This ensures that session data persists even if the cluster is destroyed or updated, providing a superior **separation of concerns** between state (data) and compute (AKS).

---

# CI/CD Pipeline Documentation

The pipeline is implemented using **GitHub Actions**, ensuring that every code change is automatically verified and deployed with minimal manual intervention.



## Pipeline Workflow
The automation follows a structured path from the repository to the live environment:

1.  **Trigger:** * The workflow is initiated automatically on every **push to the `main` branch**.
2.  **Build:** * A Docker image is built from the `src/frontend` source code.
3.  **Push:** * The image is tagged with the **GitHub Commit SHA** for traceability.
    * The image is then pushed to the **Azure Container Registry (ACR)**.
4.  **Deploy:** * The pipeline authenticates with the **AKS cluster**.
    * It updates the frontend deployment manifest to use the newly built image tag, triggering a rolling update.

---

## Strategic Benefits

### Zero-Touch Deployment
By automating the transition from the repository to the cluster, we achieve a **"Zero-Touch"** deployment model. This ensures that:
* The live environment is always a direct mirror of the version-controlled source code.
* Human error during the deployment process is significantly reduced.
* Rollbacks are simplified, as every deployment is tied to a specific Git commit.

> **Note:** Security is maintained by using GitHub Secrets to store Azure Service Principal credentials and ACR login information.