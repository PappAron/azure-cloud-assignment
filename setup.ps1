# 1. Connect to AKS
Write-Host "Connecting to AKS Cluster..." -ForegroundColor Cyan
az aks get-credentials --resource-group cloud-native-assignment-rg --name online-boutique-cluster --overwrite-existing

# 1.1. Create/Refresh CI/CD Service Principal and Sync to GitHub
Write-Host "Configuring CI/CD Identity and Syncing to GitHub..." -ForegroundColor Cyan
$SP_NAME = "online-boutique-github-identity"
$SUB_ID = (az account show --query id -o tsv)
$SP_CHECK = az ad sp list --display-name $SP_NAME --query "[].appId" -o tsv

if ($SP_CHECK) {
    Write-Host "Service Principal exists. Resetting credentials..." -ForegroundColor Yellow
    $NEW_PASS = az ad sp credential reset --id $SP_CHECK --query "password" -o tsv
    $TENANT_ID = (az account show --query tenantId -o tsv)
    $SP_JSON = @{ clientId = $SP_CHECK; clientSecret = $NEW_PASS; subscriptionId = $SUB_ID; tenantId = $TENANT_ID }
} else {
    Write-Host "Creating new Service Principal..." -ForegroundColor Yellow
    $SP_JSON = az ad sp create-for-rbac --name $SP_NAME --role "Contributor" --scopes "/subscriptions/$SUB_ID" --json-auth | ConvertFrom-Json
}

$SP_JSON | ConvertTo-Json -Compress | gh secret set AZURE_CREDENTIALS
Write-Host "Successfully synced AZURE_CREDENTIALS to GitHub!" -ForegroundColor Green

# 2. Deploy Manifests
Write-Host "Deploying Application Manifests..." -ForegroundColor Cyan
kubectl apply -f ./src/release/kubernetes-manifests.yaml

# 3. Expose Frontend
Write-Host "Exposing Frontend via LoadBalancer..." -ForegroundColor Cyan
kubectl patch service frontend -p "{\`"spec\`": {\`"type\`": \`"LoadBalancer\`"}}"

# 4. Handle Redis Integration
Write-Host "Discovering Azure Redis instance..." -ForegroundColor Cyan
$REDIS_NAME = az redis list --resource-group cloud-native-assignment-rg --query "[?contains(name, 'boutique-cart-db')].name" -o tsv
$REDIS_KEY = az redis list-keys --name $REDIS_NAME --resource-group cloud-native-assignment-rg --query "primaryKey" -o tsv
$REDIS_HOST = "$($REDIS_NAME).redis.cache.windows.net:6380"

# Create/Update the secret
kubectl create secret generic redis-secret --from-literal=redis-password=$REDIS_KEY --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Wiring CartService to Azure Redis..." -ForegroundColor Cyan

# Remove any existing broken environment variables to start fresh
kubectl set env deployment/cartservice REDIS_PASSWORD_SECRET- REDIS_PASSWORD- REDIS_ADDR-

# Apply the correct configuration using a clean Patch
$patchJson = @"
[
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "REDIS_ADDR", "value": "$REDIS_HOST"}},
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "REDIS_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "redis-secret", "key": "redis-password"}}}}
]
"@
$patchJson | kubectl patch deployment cartservice --type='json' -p $input

# 5. Install Monitoring (Prometheus Stack)
Write-Host "Installing Prometheus/Grafana Stack..." -ForegroundColor Cyan
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-stack prometheus-community/kube-prometheus-stack --set grafana.service.type=LoadBalancer --rollback-on-failure

# 6. Deploy Custom Lab Chart
Write-Host "Deploying Custom Webserver Chart..." -ForegroundColor Cyan
if (Test-Path "./helm-frontend") {
    helm upgrade --install assignment-webserver ./helm-frontend --set service.type=LoadBalancer --rollback-on-failure
    Write-Host "Custom Helm Chart deployed successfully!" -ForegroundColor Green
}

# 7. Final Refresh of IP addresses
Write-Host "`n--- REFRESHING STATUS ---" -ForegroundColor Cyan
Write-Host "Waiting for External IPs (30s)..."
Start-Sleep -Seconds 30

$FRONTEND_IP = kubectl get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
$GRAFANA_IP  = kubectl get svc kube-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
$WEBSERVER_IP = kubectl get svc assignment-webserver-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# 8. Access Verification
Write-Host "`nVerifying Access..." -ForegroundColor Cyan
if (-not $WEBSERVER_IP) {
    Write-Host "IPs pending. Starting Fallback Port-Forward on http://localhost:8888" -ForegroundColor Yellow
    kubectl port-forward svc/assignment-webserver-svc 8888:80
} else {
    Write-Host "--- ALL SERVICES LIVE ---" -ForegroundColor Green
    Write-Host "Main Application: http://$FRONTEND_IP"
    Write-Host "Grafana Dashboard: http://$GRAFANA_IP"
    Write-Host "Lab Webserver:    http://$WEBSERVER_IP"
}

Write-Host "`nTo get Grafana admin password, run:" -ForegroundColor Yellow
Write-Host "kubectl get secret kube-stack-grafana -o jsonpath='{.data.admin-password}' | %{[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$_`))}"