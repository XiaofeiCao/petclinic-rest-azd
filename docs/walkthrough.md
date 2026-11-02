# Run Petclinic REST on Azure

A manual walkthrough for deploying the template and trying its API.
No Spring extension, local JDK, or Maven installation is required; Docker builds the Java app.

## 1. Install prerequisites

- Git
- [Azure Developer CLI (`azd`)](https://aka.ms/azd-install)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- Docker with Linux containers running
- PowerShell 7 for the commands below
- An Azure subscription with resource creation and role-assignment permissions

Verify the tools:

```powershell
git --version
azd version
az version
docker info
pwsh --version
```

The deploying user needs permissions such as Contributor plus Role Based Access
Control Administrator at subscription scope. Deployment incurs Azure charges.

## 2. Sign in and initialize

Both sign-ins use your browser:

```powershell
az login
azd auth login

New-Item -ItemType Directory petclinic-rest-demo
Set-Location petclinic-rest-demo
azd init -t weidongxu-microsoft/petclinic-rest-azd
```

Choose a new environment name. Use a fresh environment rather than reusing an
older password-based or user-assigned identity deployment.

## 3. Inspect the template

```powershell
Get-Content azure.yaml
Get-Content src\main\resources\application.properties
Get-ChildItem infra
```

The app targets PostgreSQL with managed identity. The short JDBC URL identifies
the database; separate Hikari properties configure authentication and verified TLS.
Deployment supplies only `POSTGRES_URL`.

The Container App's system-assigned identity pulls its image and connects to
PostgreSQL. There is no separate identity resource, database password, or Key Vault.
See the [architecture diagram](images/architecture.png).

## 4. Deploy

```powershell
azd env set DATABASE_SIZE small
azd up
```

Choose your subscription and region when prompted. **West US 2 (`westus2`)**
was used for live validation; availability and quota still depend on your subscription.
The small database uses PostgreSQL 16, B1ms compute, and 32 GiB storage.

`azd up` builds the image, provisions infrastructure, configures database identity,
and deploys the app. No separate Bicep compilation or Maven command is needed.
The signed-in user performs administrator setup; the app runs as non-admin
`petclinic_app` and initializes its own schema and sample data.

## 5. Try the API

Read the application endpoint, including its `/petclinic` context path:

```powershell
$base = (azd env get-value SERVICE_SPRING_PETCLINIC_REST_APP_ENDPOINT_URL).TrimEnd('/')
Invoke-RestMethod -Uri "$base/actuator/health"
Invoke-RestMethod -Uri "$base/api/vets"
Start-Process "$base/swagger-ui.html"
```

Expect health `UP` and six sample veterinarians. If the app is still starting,
wait briefly and retry. This is a REST API, not the Petclinic web UI.

Create an owner and read it back:

```powershell
$owner = @{
    firstName = 'Demo'
    lastName = 'Owner'
    address = '1 Demo Street'
    city = 'Demo'
    telephone = '0123456789'
}
$created = Invoke-RestMethod -Method Post -Uri "$base/api/owners" `
    -ContentType 'application/json' -Body ($owner | ConvertTo-Json)
$created
Invoke-RestMethod -Uri "$base/api/owners/$($created.id)"
```

The returned owner should have a positive ID and match the submitted fields.
The API is public and unauthenticated: use synthetic data only.

## 6. Check restart persistence

```powershell
$subscription = azd env get-value AZURE_SUBSCRIPTION_ID
$group = azd env get-value AZURE_RESOURCE_GROUP
$revision = az containerapp show --subscription $subscription `
    --resource-group $group --name spring-petclinic-rest-app `
    --query properties.latestRevisionName --output tsv
az containerapp revision restart --subscription $subscription `
    --resource-group $group --name spring-petclinic-rest-app --revision $revision
```

After the app becomes ready again, repeat:

```powershell
Invoke-RestMethod -Uri "$base/actuator/health"
Invoke-RestMethod -Uri "$base/api/owners/$($created.id)"
```

Health should be `UP`, and the owner should retain its ID and fields.
Startup reruns the original seed SQL, so deleted sample records can reappear.

## 7. Clean up

```powershell
$subscription = azd env get-value AZURE_SUBSCRIPTION_ID
$group = azd env get-value AZURE_RESOURCE_GROUP
azd down
```

Confirm deletion when prompted. This removes the deployed resources and database
data. After deletion completes, verify that the resource group no longer exists:

```powershell
az group exists --subscription $subscription --name $group
```

Expect `false`. Do not commit the local `.azure` directory.
For bootstrap failures and temporary firewall cleanup, see
[troubleshooting](../README.md#security-and-troubleshooting).
