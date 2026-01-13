# 1. Connect to AKS
Write-Host "Connecting to AKS Cluster..." -ForegroundColor Cyan
az aks get-credentials --resource-group cloud-native-assignment-rg --name online-boutique-cluster --overwrite-existing

# 2. Deploy Manifests
Write-Host "Deploying Application Manifests..." -ForegroundColor Cyan
kubectl apply -f ./src/release/kubernetes-manifests.yaml

# 3. Expose Frontend
Write-Host "Exposing Frontend via LoadBalancer..." -ForegroundColor Cyan
kubectl patch service frontend -p "{\`"spec\`": {\`"type\`": \`"LoadBalancer\`"}}"

# 3. Handle Redis Integration (DYNAMIC)
Write-Host "Discovering Azure Redis instance..." -ForegroundColor Cyan

# Find the Redis name that starts with 'boutique-cart-db' in your resource group
$REDIS_NAME = az redis list --resource-group cloud-native-assignment-rg --query "[?contains(name, 'boutique-cart-db')].name" -o tsv

if (-not $REDIS_NAME) {
    Write-Error "Could not find a Redis instance starting with 'boutique-cart-db'!"
    exit
}

Write-Host "Found Redis: $REDIS_NAME" -ForegroundColor Yellow

# Fetch Keys and Hostname using the discovered name
$REDIS_KEY = az redis list-keys --name $REDIS_NAME --resource-group cloud-native-assignment-rg --query "primaryKey" -o tsv
$REDIS_HOST = "$($REDIS_NAME).redis.cache.windows.net:6380"

# Create Secret
kubectl create secret generic redis-secret --from-literal=redis-password=$REDIS_KEY --dry-run=client -o yaml | kubectl apply -f -

# Update CartService
Write-Host "Wiring CartService to Azure Redis..." -ForegroundColor Cyan
kubectl set env deployment/cartservice REDIS_ADDR="$($REDIS_HOST)"
kubectl set env deployment/cartservice REDIS_PASSWORD- --env=REDIS_PASSWORD_SECRET=redis-secret # Removing old, using secret ref logic

# 5. Install Monitoring (Community Helm Chart)
Write-Host "Installing Grafana Monitoring via Helm..." -ForegroundColor Cyan
# Add the official repo and update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Install the full stack
# This will install Prometheus, Grafana, and the Node Exporters automatically.
helm install kube-stack prometheus-community/kube-prometheus-stack `
  --set grafana.service.type=LoadBalancer `
  --rollback-on-failure

# 6. Deploy Custom Lab Chart (Custom Helm Chart)
Write-Host "Deploying Custom Webserver Chart (Lab Task 2 Replication)..." -ForegroundColor Cyan

# Check if the helm-frontend folder exists
if (Test-Path "./helm-frontend") {
    # We use 'upgrade --install' so the script can be run multiple times safely
    helm upgrade --install assignment-webserver ./helm-frontend `
        --set service.type=LoadBalancer `
        --atomic
    
    Write-Host "Custom Helm Chart deployed successfully!" -ForegroundColor Green
} else {
    Write-Warning "Directory ./helm-frontend not found. Skipping custom chart deployment."
}

# 7. Final Output Summary
Write-Host "`n--- REFRESHING STATUS ---" -ForegroundColor Cyan
# We sleep for 2 seconds to let the cluster update its status before we grab IPs
Start-Sleep -Seconds 2

$FRONTEND_IP = kubectl get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
$GRAFANA_IP = kubectl get svc monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
$WEBSERVER_IP = kubectl get svc assignment-webserver-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# 8. Access Verification (Improved Port-Forwarding)
Write-Host "`nVerifying Webserver Access..." -ForegroundColor Cyan
$WEBSERVER_SVC = "assignment-webserver-svc"

# If the IP is empty, we offer the Port-Forward on a safer port (8888)
if (-not $WEBSERVER_IP) {
    Write-Host "External IP for Webserver is still <pending>." -ForegroundColor Yellow
    Write-Host "Starting Port-Forwarding on http://localhost:8888 ..." -ForegroundColor Green
    Write-Host "Main Application is at: http://$FRONTEND_IP" -ForegroundColor White
    Write-Host "Press Ctrl+C to stop forwarding when done." -ForegroundColor White
    
    # Using 8888 to avoid the '8081' conflict you had earlier
    kubectl port-forward svc/$WEBSERVER_SVC 8888:80
} else {
    Write-Host "--- DEPLOYMENT COMPLETE ---" -ForegroundColor Green
    Write-Host "Main Application: http://$FRONTEND_IP" -ForegroundColor White
    Write-Host "Grafana Dashboard: http://$GRAFANA_IP" -ForegroundColor White
    Write-Host "Lab Webserver:    http://$WEBSERVER_IP" -ForegroundColor White
}

Write-Host "`nTo get Grafana admin password, run:" -ForegroundColor Yellow
Write-Host "kubectl get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | %{[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$_`))}"