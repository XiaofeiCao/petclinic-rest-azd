# Petclinic REST on Azure

A standalone azd template for the Spring Petclinic REST API (no web UI) on
Azure Container Apps with PostgreSQL 16. Managed identity authenticates to the
database and Container Registry; no database password or Key Vault is needed.
The `azure.springboot` extension required by `azure.yaml` packages the application,
deploys the service module, and reconciles PostgreSQL access. The `springbootapp`
host builds with the Maven Wrapper and generates its own temporary runtime
Dockerfile; the template does not need an authored Dockerfile or `docker:` block.
Docker must still be installed and running for packaging.

**Demo only:** the API is public and unauthenticated. The app is a non-admin
database user, but can create and manage its own tables. Do not use sensitive data.

## Architecture

![Petclinic REST architecture](docs/images/architecture.png)

See the [editable diagram](docs/images/architecture.svg) and
[gallery submission assets](docs/gallery.md).
The app and temporary job have distinct system-assigned identities. The job's
temporary PostgreSQL administrator registration refers to that same job
principal, not a third identity or an Azure RBAC role assignment.

## Deploy

This branch requires a development build of the `azure.springboot` extension
with extension-owned PostgreSQL job bootstrap support; installing azd alone
does not provide that unreleased capability. See the
[extension development instructions](https://github.com/XiaofeiCao/azure-dev/blob/xiaofeicao-spring-boot-template-roadmap/cli/azd/extensions/azure.springboot/README.md#local-development-installation)
on the `xiaofeicao-spring-boot-template-roadmap` branch. Pull that branch and install
its matching local bundle **before `azd init`**, not just before deployment.
Building the extension from source requires Go 1.26.4 or newer. The bundle route
does not require `azd x publish` or a local extension registry.
The deployment also needs its release-configured bootstrap runner image.

Install [azd](https://aka.ms/azd-install) 1.37.2 or newer, JDK 17+ and Docker.
Start Docker for packaging and sign in to azd with a User account that can access
the target subscription; a second Azure CLI login is not required for deployment:

```sh
azd auth login
azd init -t https://github.com/XiaofeiCao/petclinic-rest-azd --branch postgres-job-bootstrap
azd up
```

Choose an environment, subscription, location, and database size.
No manual subscription or administrator `azd env set` is needed for this
interactive flow. The extension prompts for a missing administrator User object
ID, with azd's current User in the selected subscription's resource tenant as
the default, then asks for the selected User's missing principal name. Enter
another User's object ID to select a different administrator. The extension
does not decode tokens, query Microsoft Graph, or derive a name from an object ID.

Valid configured `DATABASE_ADMIN_NAME` and `DATABASE_ADMIN_OBJECT_ID` values
bypass their respective prompts for `azd up` and standalone `azd provision`.
A name alone never selects another principal.
The `SPRING_DATABASE_ADMINISTRATOR_NAME`/`SPRING_DATABASE_ADMINISTRATOR_OBJECT_ID`
aliases must agree with these inputs. Saved administrator values are preserved
when another User deploys the environment. Do not use a client/application ID
instead of the User's object ID. Invalid interactive responses can be corrected;
canceling saves no partial administrator selection. Prompt validation checks
input format, not directory identity.

For `--no-prompt`, supply the administrator name through the supported
environment inputs before provisioning; an absent object ID uses the current
User. Supply the object ID too to select another User. Missing names and
conflicting inputs fail before identity preparation or extension writes.
Native subscription/location inputs must also be available for automation.

| Size | Compute | Storage |
|---|---|---|
| `small` (default) | B1ms: 1 vCore, 2 GiB RAM | 32 GiB |
| `larger` | B2s: 2 vCores, 4 GiB RAM | 32 GiB |

Both are burstable demo configurations, not production tiers. Regional SKU
availability and subscription quota apply. For automation, set `DATABASE_SIZE`
with `azd env set` before provisioning; `--no-prompt` uses small unless saved.

### Subscriptions requiring VNet integration

The default deployment does not create a customer-managed VNet. If Azure Policy
requires the Container Apps environment to use one, select a fresh environment
and enable the published option **before the first provision**:

```sh
azd env set AZURE_USE_VNET true
azd up
```

This template substitution selects the Bicep `useVirtualNetwork` parameter.
It creates a dedicated VNet and `/23` infrastructure subnet; HTTPS ingress and
the PostgreSQL endpoint remain public. It does not create private endpoints,
a NAT gateway, or policy-exemption tags. The extension still reconciles only
the Container Apps environment's exact outbound-IP database firewall rules.
VNet integration is fixed when the environment is created; do not toggle this
setting on an existing deployment. Use a fresh environment to change topology.

Use a **fresh environment** when upgrading from a password-based or
user-assigned-identity version.
Reprovisioning does not migrate data or delete retired MySQL, Key Vault, jobs,
identities, secrets, or permissions.

The deploying identity needs resource creation and role-assignment permissions,
such as Contributor plus Role Based Access Control Administrator at subscription
scope, plus permission to manage Container Apps Jobs and PostgreSQL Entra
administrators. The extension's supported `preprovision` lifecycle event prepares
the selected administrator for both `azd up` and standalone `azd provision`.
There are no template preflight/preup preparation hooks. azd owns normal
subscription/location selection; the extension uses host principal and
`LookupTenant` APIs with the existing User login. The user-access tenant for
credentials is distinct from the administrator's resource tenant.
Service-principal-only provisioning is not supported.

The required name/ID parameters keep their deferred bindings so initial Bicep
provider setup can finish before the lifecycle event. The extension rejects
invalid/conflicting configured inputs before identity preparation or state writes,
then supplies real values for azd's parameter reload. Placeholders are never
valid administrator inputs. The tested API rejects actual name omission; the
template must still send `principalName`. Its resource architecture is unchanged.

Provisioning first creates the Container App with a public placeholder and its
system-assigned identity, grants that principal `AcrPull` on the registry, and
configures registry authentication as `system`. The service deployment keeps the
same identity when switching to the private application image. Reprovisioning
preserves the running image and identity.

The recorded E2E used separate `azd provision` and
`azd deploy spring-petclinic-rest-app` commands, with a registry-scoped `AcrPull`
verification between them. This verification is an explicit test-harness step,
not an additional template hook.

After provisioning, the extension verifies the exact Container Apps outbound-IP
firewall rules and maps the application identity to `petclinic_app`. SQL
reconciliation runs from a short-lived Container Apps job in the deployed
environment. The job receives temporary administrator access only for the bounded
execution window, then the extension removes that access before deleting the job.
The job has its own system-assigned identity, distinct from the application's.
Its temporary PostgreSQL Entra administrator registration authorizes that same
job principal; it is not another identity or an Azure RBAC role assignment.
No unrestricted PostgreSQL firewall rule is created.

The infrastructure serializes PostgreSQL database creation, TLS configuration,
exact-IP firewall rules and administrator registration. Flexible Server can reject
overlapping child-resource writes with `ServerIsBusy`.

Petclinic runs its original schema and seed SQL at startup. Restarting can restore
deleted sample records. Azure activates the passwordless `azure-postgres` profile;
the existing password-based `postgres` profile remains available for explicit local
development.

## Call the API

Use the app hostname from the HTTPS endpoint printed by azd:

| Endpoint | URL |
|---|---|
| Vets API | `https://<app-host>/petclinic/api/vets` |
| Swagger UI | `https://<app-host>/petclinic/swagger-ui.html` |
| Health | `https://<app-host>/petclinic/actuator/health` |

```sh
curl "https://<app-host>/petclinic/api/vets"
```

## Run locally

With JDK 17 installed, run from the project root:

```sh
./mvnw spring-boot:run
```

On Windows PowerShell, use `.\mvnw.cmd spring-boot:run`.
The default `h2,spring-data-jpa` profiles use an in-memory database; no Azure
resources or firewall changes are needed. Data is lost when the process stops.
Open [Swagger UI](http://localhost:9966/petclinic/swagger-ui.html),
[the vets API](http://localhost:9966/petclinic/api/vets), or
[health](http://localhost:9966/petclinic/actuator/health). Stop with Ctrl+C.

## Security and troubleshooting

- Ingress is HTTPS-only; the bootstrap image has no public ingress.
- PostgreSQL password authentication is disabled. The JDBC authentication plugin
  obtains tokens using the app's system-assigned managed identity, without an
  `azure.clientId` or `AZURE_CLIENT_ID` selector.
- Database connections verify the TLS certificate and hostname.
- The app owns its tables and has `USAGE, CREATE` on the `public` schema.
  It is not a read/write-only database role.
- Firewall rules named `aca-<IPv4-address-with-hyphens>` are template-owned.
  Reprovisioning removes obsolete rules and preserves unrelated rules, which can
  grant additional access. Reprovision if app outbound IPs change.
- A customer-managed VNet is created only when `AZURE_USE_VNET=true` is selected
  before provisioning. Neither topology creates private endpoints or a
  fixed-egress NAT gateway. An IP firewall is not workload identity isolation;
  database authentication remains required.
- Do not commit `.azure/` or publish its contents.

If identity bootstrap fails, check the signed-in tenant and the redacted Container
Apps job diagnostic printed by the extension. Rerun `azd provision` after
correcting the cause. Do not add an unrestricted PostgreSQL firewall rule.

On macOS or Linux, `mvnw` must be executable. If an existing copy reports
`permission denied` when azd invokes `mvnw`, run `chmod +x ./mvnw`, then retry
`azd up`. Fresh copies from this branch include the executable permission.

## Clean up

```sh
azd down
```

This deletes the database and application resources, including their data.
Database, container, registry, and logging usage incur Azure charges.

## Local checks and upstream source

With JDK 17, Azure CLI and PowerShell 7 installed for these local helper checks,
plus the packaging prerequisites:

```sh
./mvnw --batch-mode --no-transfer-progress verify
az bicep build --file infra/main.bicep
az bicep build --file infra/application.bicep
pwsh -File tests/Test-ManagedIdentityProfile.ps1
```

Initialize a local azd environment with `azd init -e local-check --no-prompt` if
needed. Then package the application and run the database check in PowerShell 7.
Use the image reference from that exact package result rather than selecting a
previously cached Docker image:

```powershell
$packageJson = azd package --no-prompt --output json
if ($LASTEXITCODE -ne 0) { throw 'Application packaging failed.' }
$package = ($packageJson -join "`n") | ConvertFrom-Json
$images = @($package.services.'spring-petclinic-rest-app'.artifacts |
    Where-Object { $_.kind -eq 'container' -and $_.locationKind -eq 'local' })
if ($images.Count -ne 1 -or [string]::IsNullOrWhiteSpace($images[0].location)) {
    throw 'Expected exactly one packaged local application image.'
}
pwsh -File tests\Test-ApplicationDatabase.ps1 -ApplicationImage $images[0].location
```

The database test checks non-root OS execution and non-admin application startup
and restart with a local password fixture, not Azure authentication. These
packaging and database checks do not provision Azure resources.
The managed-identity profile test
checks template wiring and profile separation; a live Azure deployment is needed
to verify managed identity and extension-owned SQL bootstrap end-to-end.

CI builds the pinned public prototype revision in
`.github/workflows/validate.yml` for packaging and local database checks only.
That fixture is not a released extension and does not validate Azure deployment
or PostgreSQL managed-identity bootstrap.

`src/main/java/` is unchanged from upstream commit
[`afc8fc1`](https://github.com/spring-petclinic/spring-petclinic-rest/tree/afc8fc1d3b8ec8de69414482b3bd70a1da78cb95).
The template adds `application-azure-postgres.properties` for the passwordless
Azure profile, and `pom.xml` adds `azure-identity-extensions` for passwordless JDBC authentication.
See [UPSTREAM.md](UPSTREAM.md), [NOTICE](NOTICE), and [LICENSE.txt](LICENSE.txt).

### Validated development lifecycle

Application and infrastructure revision
[`d0dd45c`](https://github.com/XiaofeiCao/petclinic-rest-azd/tree/d0dd45cd6aa16ed62ee7e4142ebb70935e183bcd)
passed initial deployment, repeat deployment and revision restart, and
reprovisioning with the same application principal and persistent non-seed
record. Every stage passed REST create/read/update/delete checks, Entra-only
authentication, verified TLS, exact egress firewall rules, and temporary
job/administrator cleanup.

This used a development extension build and a session-only bootstrap-runner
accommodation, not an unmodified released extension or a released production
runner. Azure accepted asynchronous deletion of the owned test environment;
deletion completion was not polled or claimed. The diagram update changes
documentation assets only; the validated application and infrastructure
payload is unchanged.
