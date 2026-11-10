param location string
param useVirtualNetwork bool = false

var token = uniqueString(resourceGroup().id)

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acrpetclinic${token}'
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-petclinic-${token}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource network 'Microsoft.Network/virtualNetworks@2024-05-01' = if (useVirtualNetwork) {
  name: 'vnet-petclinic-${token}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'container-apps-infrastructure'
        properties: {
          addressPrefix: '10.0.0.0/23'
        }
      }
    ]
  }
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-petclinic-${token}'
  location: location
  properties: {
    vnetConfiguration: useVirtualNetwork ? {
      infrastructureSubnetId: '${network!.id}/subnets/container-apps-infrastructure'
      internal: false
    } : null
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
  }
}

output registryEndpoint string = registry.properties.loginServer
output registryName string = registry.name
output environmentId string = environment.id
output virtualNetworkId string = useVirtualNetwork ? network!.id : ''
