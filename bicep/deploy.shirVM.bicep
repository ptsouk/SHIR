@description('Username for the Virtual Machine.')
param adminUsername string

@description('Password for the Virtual Machine.')
@minLength(12)
@secure()
param adminPassword string

@description('auth key for shir registration.')
@secure()
param shirSecret string

@description('The Windows version for the VM. This will pick a fully patched image of this given Windows version.')
@allowed([
  '2022-datacenter-azure-edition'
])
param OSVersion string

@description('Size of the virtual machine.')
param vmSize string

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Name of the virtual machine.')
param vmName string

@description('Security Type of the Virtual Machine.')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'TrustedLaunch'
param subnetId string
param principalId string
param identityId string
param storageAccountName string
param containerName string
param tags object

var nicName = '${vmName}-${uniqueString(resourceGroup().id)}'
var securityProfileJson = {
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
  securityType: securityType
}
var extensionName = 'InstallSHIR'
var extensionType = 'CustomScriptExtension'
var extensionPublisher = 'Microsoft.Compute'
var extensionVersion = '1.10'

var storageURL = environment().suffixes.storage

var settings = {
      timestamp: 123456789
    }
var protectedSettings = {
  commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File install-IntegrationRuntime.ps1 -authKey ${shirSecret}'
  fileUris: [
    'https://${storageAccountName}.blob.${storageURL}/${containerName}/install-IntegrationRuntime.ps1', 'https://${storageAccountName}.blob.${storageURL}/${containerName}/IntegrationRuntime.msi'
  ]
  managedIdentity: {
    objectId: principalId
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2022-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
  tags: tags
}

resource vm 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: vmName
  location: location
  tags: tags  
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: OSVersion
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    securityProfile: ((securityType == 'TrustedLaunch') ? securityProfileJson : null)
  }
}

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  parent: vm
  tags: tags
  name: extensionName
  location: location
  properties: {
    publisher: extensionPublisher
    type: extensionType
    typeHandlerVersion: extensionVersion
    settings: settings
    protectedSettings: protectedSettings
  }
}
