param keyvaultConnectionName string
param keyVaultName string
param purviewAccountName string
param logicAppName string
param location string = resourceGroup().location
param tags object

resource keyvaultConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: keyvaultConnectionName
  location: location
  tags: tags
  properties: {
    displayName: keyvaultConnectionName
    api: {
      name: keyvaultConnectionName
      id: 'subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/${keyvaultConnectionName}'
      type: 'Microsoft.Web/locations/managedApis'
    }
    parameterValueSet: {
      name: 'oauthMI'
      values: {
        vaultName: {
          value: keyVaultName
        }
      }
    }
  }
}

resource logicApp 'Microsoft.Logic/workflows@2017-07-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        'Key Vault Name': {
          defaultValue: keyVaultName
          type: 'String'
        }
        'Purview Account Name': {
          defaultValue: purviewAccountName
          type: 'String'
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {}
        }
      }
      actions: {
        Create_SHIR_Secret: {
          runAfter: {
            'Integration_Runtimes_-_List_Auth_Keys': [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            authentication: {
              audience: 'https://vault.azure.net'
              type: 'ManagedServiceIdentity'
            }
            body: {
              value: '@body(\'Integration_Runtimes_-_List_Auth_Keys\')[\'authKey1\']'
            }
            method: 'PUT'
            uri: 'https://@{parameters(\'Key Vault Name\')}.vault.azure.net/secrets/@{triggerOutputs()[\'headers\'][\'SHIRName\']}?api-version=7.4'
          }
          runtimeConfiguration: {
            secureData: {
              properties: [
                'inputs'
                'outputs'
              ]
            }
          }
        }
        Get_SPN_clientID: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'purview-CreateSHIRclientID\')}/value'
          }
          runtimeConfiguration: {
            secureData: {
              properties: [
                'outputs'
              ]
            }
          }
        }
        Get_SPN_secret: {
          runAfter: {
            Get_SPN_clientID: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'purview-CreateSHIRsecret\')}/value'
          }
          runtimeConfiguration: {
            secureData: {
              properties: [
                'outputs'
              ]
            }
          }
        }
        'Integration_Runtimes_-_Create_Or_Replace': {
          runAfter: {
            Get_SPN_secret: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            authentication: {
              audience: 'https://purview.azure.net'
              clientId: '@body(\'Get_SPN_clientID\')?[\'value\']'
              secret: '@body(\'Get_SPN_secret\')?[\'value\']'
              tenant: tenant().tenantId
              type: 'ActiveDirectoryOAuth'
            }
            body: {
              kind: 'SelfHosted'
              properties: {
                description: 'My integrationruntime description'
              }
            }
            method: 'PUT'
            uri: 'https://@{parameters(\'Purview Account Name\')}.purview.azure.com/scan/integrationruntimes/@{triggerOutputs()[\'headers\'].SHIRName}?api-version=2022-07-01-preview'
          }
          runtimeConfiguration: {
            secureData: {
              properties: [
                'inputs'
              ]
            }
          }
        }
        'Integration_Runtimes_-_List_Auth_Keys': {
          runAfter: {
            'Integration_Runtimes_-_Create_Or_Replace': [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            authentication: {
              audience: 'https://purview.azure.net'
              clientId: '@body(\'Get_SPN_clientID\')?[\'value\']'
              secret: '@body(\'Get_SPN_secret\')?[\'value\']'
              tenant: tenant().tenantId
              type: 'ActiveDirectoryOAuth'
            }
            method: 'POST'
            uri: 'https://@{parameters(\'Purview Account Name\')}.purview.azure.com/scan/integrationruntimes/@{triggerOutputs()[\'headers\'].SHIRName}/:listAuthKeys?api-version=2022-07-01-preview'
          }
          runtimeConfiguration: {
            secureData: {
              properties: [
                'inputs'
              ]
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          keyvault: {
            connectionId: resourceId('Microsoft.Web/connections', keyvaultConnectionName)
            connectionName: keyvaultConnectionName
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
            id: 'subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/${keyvaultConnectionName}'
          }
        }
      }
    }
  }
  dependsOn: [
    keyvaultConnection
  ]
}

resource kvAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  name: '${keyVaultName}/add'
  properties: {
    accessPolicies: [
      {
        tenantId: tenant().tenantId
        objectId: logicApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
          ]
        }
      }
    ]
  }
  dependsOn: [
    logicApp
  ]
}
