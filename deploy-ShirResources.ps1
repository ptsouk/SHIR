# define environment parameters
 # the tenant containing the purview account resource
$tenantId = "f6279e07-c6ac-45ee-a551-12a2fdf33d14"
 # the subscription Id containing the purview resources
$purviewSubscriptionId = "8ec43e9c-d13a-4219-a0d5-43292d705a78" 
 # the resource group containing the purview resources
$purviewResourceGroupName = "purview-rg" 
 # the purview account resource name
$purviewAccountName = "myTestPurviewAccount-01"
 # the name of the key vault containing all secrets (assuming in the same resource group as the purview account)
$keyVaultName = "mypurview-kv"
 # the name of the logic app that will be used to create the SHIR pool and publish the registration key to the key vault
$logicAppName = "shir-la"
 # the storage account containing the Custom Script Extension scripts and files
$storageAccountName = "purviewscriptssta"
 # the name of the container in the storage account containing the Custom Script Extension scripts and files
$containerName = "shirscripts"

# define SHIR parameters
 # the subscription Id to deploy the shir resources to
$shirSubscriptionId = "795ed07b-f150-4728-b325-c7c82d6534aa" 
 # the target resource group for the shir VM
$shirResourceGroupName = "purviewshir-rg"
 # the purview SHIR pool name
$shirPoolName = "shirPool01"
 # SHIR VM name
$vmName = "shir01-vm"
 # SHIR VM subnet resource Id
$subnetId = "/subscriptions/$shirSubscriptionId/resourceGroups/$shirResourceGroupName/providers/Microsoft.Network/virtualNetworks/myVnet01/subnets/tier2"

# connect
Connect-AzAccount -TenantId $tenantId -subscription $purviewSubscriptionId 

# deploy logic app
New-AzResourceGroupDeployment `
    -ResourceGroupName $purviewResourceGroupName `
    -TemplateFile './bicep/deploy.logicApp.bicep' `
    -TemplateParameterFile './bicep/parameters/deploy.logicApp.parameters.json' `
    -purviewAccountName $purviewAccountName `
    -keyVaultName $keyVaultName `
    -logicAppName $logicAppName `
    -DeploymentDebugLogLevel 'All' `
    -Verbose

# set context to the purview subscription
Set-AzContext -TenantId $tenantId -SubscriptionId $purviewSubscriptionId

# trigger logic app that publishes the SHIR pool registration key to the key vault
$Uri = (Get-AzLogicAppTriggerCallbackUrl -ResourceGroupName $purviewResourceGroupName -Name $logicAppName -TriggerName (Get-AzLogicAppTrigger -ResourceGroupName $purviewResourceGroupName -Name $logicAppName).Name).Value
Invoke-RestMethod -Method Post -Uri $Uri -Body "{}" -Headers @{'SHIRName' = $shirPoolName } -ContentType "application/json"
Start-Sleep -Seconds 10
# get the current version of the shir secret
$shirSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $shirPoolName -AsPlainText | ConvertTo-SecureString -AsPlainText

# deploy userAssignedIdentity
$deployUserAssignedIdentity = New-AzResourceGroupDeployment `
    -ResourceGroupName $purviewResourceGroupName `
    -TemplateFile './bicep/deploy.userAssignedIdentity.bicep' `
    -TemplateParameterFile './bicep/parameters/deploy.userAssignedIdentity.parameters.json' `
    -storageAccountName $storageAccountName `
    -DeploymentDebugLogLevel 'All' `
    -Verbose

# set context to the shir subscription
Set-AzContext -TenantId $tenantId -SubscriptionId $shirSubscriptionId

# deploy VM & Extension
New-AzResourceGroupDeployment `
    -ResourceGroupName $shirResourceGroupName `
    -TemplateFile './bicep/deploy.shirVM.bicep' `
    -TemplateParameterFile './bicep/parameters/deploy.shirVM.parameters.json' `
    -storageAccountName $storageAccountName `
    -containerName $containerName `
    -vmName $vmName `
    -subnetId $subnetId `
    -principalId $deployUserAssignedIdentity.Outputs.principalId.Value `
    -identityId $deployUserAssignedIdentity.Outputs.identityId.Value `
    -shirSecret $shirSecret `
    -DeploymentDebugLogLevel 'All' `
    -Verbose
