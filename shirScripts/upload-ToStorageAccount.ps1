$VerbosePreference="Continue"
$ErrorActionPreference = "Stop"

$ProductName = "Microsoft Integration Runtime"
$tenantId = "f6279e07-c6ac-45ee-a551-12a2fdf33d14"
$storageAccountSubscriptionId = "8ec43e9c-d13a-4219-a0d5-43292d705a78"
$storageAccountResourceGroupName = "purview-rg"
$storageAccountName = "purviewscriptssta"
$containerName = "shirscripts"

function Get-PushedIntegrationRuntimeVersion() {
    $latestIR = Get-RedirectedUrl "https://go.microsoft.com/fwlink/?linkid=839822"
    $item = $latestIR.split("/") | Select-Object -Last 1
    if ($null -eq $item -or $item -notlike "IntegrationRuntime*") {
        throw "Can't get pushed $ProductName info"
    }

    $regexp = '^IntegrationRuntime_(\d+\.\d+\.\d+\.\d+)\s*\.msi$'

    $version = [regex]::Match($item, $regexp).Groups[1].Value
    if ($null -eq $version) {
        throw "Can't get version from $ProductName download uri"
    }

    Write-Verbose "Pushed $ProductName version is $version"

    return $version
}

function Get-IntegrationRuntimeInstaller([string] $folder, [string] $version) {
    $uri = Get-InstallerUrl $version
    $output = Join-Path $folder "IntegrationRuntime.msi"
    Write-Verbose "Start to download $ProductName installer of version $version from $uri to $folder"
    (New-Object System.Net.WebClient).DownloadFile($uri, $output)

    if (-Not (Test-Path $output -PathType Leaf)) {
        throw "Cannot download $ProductName installer of version $version"
    }

    Write-Verbose "$ProductName installer has been downloaded to $output."
    return $output
}

function Get-InstallerUrl([string] $version) {
    $uri = Get-RedirectedUrl
    $uri = $uri.Substring(0, $uri.LastIndexOf('/') + 1)
    $uri += "IntegrationRuntime_$version.msi"

    return $uri
}

function Get-RedirectedUrl {
    $URL = "https://go.microsoft.com/fwlink/?linkid=839822"

    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect = $false
    $response = $request.GetResponse()

    If ($response.StatusCode -eq "Found") {
        $response.GetResponseHeader("Location")
    }
}

function New-TempDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    return (New-Item -ItemType Directory -Path (Join-Path $parent $name))
}

# Main

Write-Output "Start to download $ProductName installer."

$tmpFolder = New-TempDirectory
$version = Get-PushedIntegrationRuntimeVersion
$installerPath = Get-IntegrationRuntimeInstaller $tmpFolder $version
if (-Not (Test-Path -Path $installerPath -PathType Leaf)) {
    Write-Error "The installer $installerPath doesn't exist."
    Exit
}

# upload to storage account

Write-Output "Getting Storage Account Context"
Set-AzContext -Subscription $storageAccountSubscriptionId -TenantId $tenantId
$storageContext = (Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName -ErrorAction Stop).Context

Write-Output "Uploading $ProductName installer to storage account $storageAccountName."
$blob = @{
    File      = $installerPath
    Container = $containerName
    Blob      = "IntegrationRuntime.msi"
    Context   = $storageContext
}
Set-AzStorageBlobContent @blob -Force

Write-Output "Uploading script installer to storage account $storageAccountName."
$blob = @{
    File      = "./shirScripts/scripts/install-IntegrationRuntime.ps1"
    Container = $containerName
    Blob      = "install-IntegrationRuntime.ps1"
    Context   = $storageContext
}
Set-AzStorageBlobContent @blob -Force

Remove-Item $installerPath
Write-Output "Clean up downloaded $ProductName installer: $installerPath."
Write-Output "Finished."