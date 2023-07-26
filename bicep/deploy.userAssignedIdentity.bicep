param name string
param storageAccountName string
param location string = resourceGroup().location
param tags object

var role = {
  'Storage Blob Data Reader': '/providers/Microsoft.Authorization/roleDefinitions/2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' existing = {
  name: storageAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, userAssignedIdentity.name, role['Storage Blob Data Reader'])
  scope: storageAccount
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: role['Storage Blob Data Reader']
  }
}

output principalId string = userAssignedIdentity.properties.principalId
output identityId string = userAssignedIdentity.id
