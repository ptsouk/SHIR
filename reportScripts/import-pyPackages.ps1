# Automation Account paramaters
$tenantId = "f6279e07-c6ac-45ee-a551-12a2fdf33d14"
$subscriptionId = "8ec43e9c-d13a-4219-a0d5-43292d705a78"
$resourceGroup = "purview-rg"
$automationAccount = "purview-aa"
$runbookName = "ImportPackageFrompypi"

Connect-AzAccount -TenantId $tenantId -subscription $subscriptionId

$packages = @(
    @{name = "PyYAML";version = "6.0.1"}
    @{name = "requests";version = "2.31.0"}
    @{name = "reportlab";version = "4.0.4"}
    @{name = "msal";version = "1.23.0"}
    @{name = "azure-storage-blob";version = "12.17.0"}
    @{name = "typing-extensions";version = "4.7.1"}
    @{name = "azure-core";version = "1.28.0"}
)

foreach ($package in $packages)
{
    $params = [ordered]@{
        "param1" = "-s $subscriptionId"
        "param2" = "-g $resourceGroup"
        "param3" = "-a $automationAccount"
        "param4" = "-m $($package.name)"
        "param5" = "-v $($package.version)"
    }

    Start-AzAutomationRunbook `
        -AutomationAccountName $automationAccount `
        -Name $runbookName `
        -ResourceGroupName $resourceGroup `
        -Parameters $params `
        -Wait
}