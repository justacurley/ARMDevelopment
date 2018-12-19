#Requires -Version 3.0
function Build-Outputs { 
    <#
        .SYNOPSIS
        
        .DESCRIPTION
    
        .NOTES
    
        .PARAMETER PesterSpace
    
        .PARAMETER RootPath
    
        .EXAMPLE
    
        .EXAMPLE
    
        .FUNCTIONALITY
            PowerShell Language
    
    #>
    Param(
        [parameter(Mandatory)]
        [validateSet('eastus2','centralus')]
        [string] $ResourceGroupLocation,

        [parameter(Mandatory)]
        [string] $ResourceGroupName,

        [parameter(Mandatory)]
        [string] $StorageAccountName,

        #build user-unique container name name
        [parameter(Mandatory=$false)]
        [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant().Replace('_','') + '-' + ($env:username).tolower().replace('adm-','').replace('_','').replace('.','') + '-stageartifacts',
        
        #should almost always be deploy-ALL.json
        [parameter(Mandatory)] 
        [ValidateScript({validatePath $_})]        
        [System.IO.FileInfo] $TemplateFile,

        [parameter(Mandatory)]
        [ValidateScript({validatePath $_})] 
        [System.IO.FileInfo] $TemplateParametersFile,

        #This should be the full path to root of your local repo
        [parameter(Mandatory)]
        [ValidateScript({validatePath $_})] 
        [System.IO.FileInfo] $RootPath,

        #Directories that contain template files (ex. Linked Templates)
        [parameter(Mandatory=$false)]        
        [string[]] $additionalTemplateDirectories,

        #Optionally provide a path to stage templates
        [parameter(Mandatory=$false)]
        [ValidateScript({validatePath $_})] 
        [System.IO.FileInfo] $ArtifactStagingDirectory,

        [parameter(Mandatory=$false)]
        [string] $csvPath,

        #used for deployment purposes --- optional param
        [parameter(Mandatory=$false)]
        [hashtable] $OptionalParameters,
        
        [parameter(Mandatory)]
        [validateSet("0-azuredeploy-ALL.json","4-azuredeploy-ILBalancer.json","6-azuredeploy-WAF.json","7-azuredeploy-VM-NoDataDisks.json","7-azuredeploy-VM.json","9-azuredeploy-ASP.json","9-azuredeploy-ElasticPool.json","9-azuredeploy-PaaSApp.json","9-azuredeploy-PaaSAppDeploymentSlot.json","9-azuredeploy-SQLPaas-ElasticPool.json","9-azuredeploy-SQLPaaSDB.json","dataDisks.json","vNic.json")]
        [string]$injectOutputTemplate = "0-azuredeploy-ALL.json"
        )

    $ErrorActionPreference = 'Stop'
    try {
        [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-$UI$($host.name)".replace(' ','_'), '3.0.0')
    } catch { }
    function Format-ValidationOutput {
        param ($ValidationOutput, [int] $Depth = 0)
        Set-StrictMode -Off
        return @($ValidationOutput | Where-Object { $_ -ne $null } | ForEach-Object { @('  ' * $Depth + ': ' + $_.Message) + @(Format-ValidationOutput @($_.Details) ($Depth + 1)) })
    }
    if( $OptionalParameters -eq $null ) 
    {
        $OptionalParameters = New-Object -TypeName Hashtable
    }

    # Build and confirm all paths
    #convert FileInfo's to strings
    [string]$TemplateFile               = $TemplateFile
    [string]$TemplateParametersFile     = $TemplateParametersFile
    [string]$RootPath                   = $RootPath
    [string]$ArtifactStagingDirectory   = $ArtifactStagingDirectory
    if (!$ArtifactStagingDirectory){
        $ArtifactStagingDirectory = join-path ([system.io.path]::GetFullPath($env:temp)) -childPath $storageContainerName
    }
    $rootPath = $rootPath.trimEnd('\')
    # if (!(Test-Path $csvPath)){
    #     New-Item -ItemType Directory -Path $csvPath
    # }

    # Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
    $JsonParameters = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
    if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
        $JsonParameters = $JsonParameters.parameters
    }
    
    $ArtifactsLocationName = '_artifactsLocation'
    $ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'
    $OptionalParameters[$ArtifactsLocationName] = $JsonParameters | Select -Expand $ArtifactsLocationName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore
    $OptionalParameters[$ArtifactsLocationSasTokenName] = $JsonParameters | Select -Expand $ArtifactsLocationSasTokenName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore
    
    # Create a storage account name if none was provided
    Write-Host "Getting Storage Account Context for $storageAccountName" -ForegroundColor green 
    $StorageAccount = (Get-AzureRmStorageAccount | Where StorageAccountName -eq $StorageAccountName)

    # Generate the value for artifacts location if it is not provided in the parameter file
    if ($OptionalParameters[$ArtifactsLocationName] -eq $null) {
        $OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
    }

    #Create Blob Container, fail silently if it already exists 
    New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1   
    
    Write-Host "Copying templates to Staging Directory" -ForegroundColor green 
    #copy all template files to $env:temp 
    copytoStage -root $rootPath -additionalDir $additionalTemplateDirectories -stagePath $artifactStagingDirectory  
    #remove all non-deployment resources  
    $ArtifactFilePaths = (Get-ChildItem -Path $artifactStagingDirectory -File -Recurse -filter *.json)
    Write-Host "Clearing non-deployment resources" -ForegroundColor green 
    clearResources $ArtifactFilePaths
    #inject output object provided by user
    Write-Host "Creating outputs from variables of $injectOutputTemplate" -ForegroundColor Green
    $filePath = $ArtifactFilePaths | ? Name -match $injectOutputTemplate 
    variableToOutput -templateFile $filePath.FullName
    
    Write-Host "Uploading templates" -ForegroundColor Green
    #upload edited template files to container    
    foreach ($SourcePath in $ArtifactFilePaths.fullName) {
        Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($stagePath.length + 1) `
            -Container $StorageContainerName -Context $StorageAccount.Context -Force | Out-Null
    }

    #point $templateFile to new azuredeploy-All.json
    $templateFileLeaf = Split-Path $templateFile -Leaf
    $templateFile = ($ArtifactFilePaths | ? Name -match $templateFileLeaf).FullName

    # Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
    if ($OptionalParameters[$ArtifactsLocationSasTokenName] -eq $null) {
        $OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString -AsPlainText -Force `
            (New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
    }    
    
    # Create or update the resource group using the specified template file and template parameters file
    $rgExists = Get-AzureRmResourceGroup  -Name $ResourceGroupName -Location $ResourceGroupLocation
    if (!$rgExists)
    {
        throw "Please request to have a resource group created."
        #New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force
    }

    
    try {
        $debugPreference = 'Continue'
        Write-Host -ForegroundColor Green "Getting Debug from Test-AzureRMResourceGroupDeployment..." -NoNewline
        $rawResponse = (Test-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName `
        -TemplateFile $templateFile `
        -TemplateParameterFile $templateParametersFile `
        @OptionalParameters `
        -ErrorAction Stop 5>&1)
        $deploymentOutput = ($rawResponse.Item(32) -split 'Body:' | Select-Object -Skip 1 | ConvertFrom-Json).properties
        $deploymentOutputError = ($rawResponse.Item(32) -split 'Body:' | Select-Object -Skip 1 | ConvertFrom-Json).error
        Write-Host 'Success'
    }
    catch {
        Write-Host -foregroundcolor red 'Fail' 
        $rawDeployError = $_
        return $rawDeployError
        break
    }  

          
    $debugPreference = 'silentlycontinue'
    $deploymentObj = New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmmss')) `
                                        -ResourceGroupName $ResourceGroupName `
                                        -TemplateFile $TemplateFile `
                                        -TemplateParameterFile $TemplateParametersFile `
                                        @OptionalParameters `
                                        -Force -Verbose `
                                        -ErrorVariable ErrorMessages 
                                        
    if ($ErrorMessages) {
        Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
        if( $ErrorMessages.Exception.Body -ne $null )
        {
            Write-Output "Details"
            Write-Output ($ErrorMessages.Exception.Body.Details | ForEach-Object { ("{0}: {1}" -f $_.Code, $_.Message) } )

        }
        
            Write-Host 'Trying to get correct output types...'                
            Get-CorrectTypes -ErrorMessages $ErrorMessages -csvPath (($filePath.FullName).Replace('.json','.csv'))
        
    }
    else { 
        $deploymentName=$deploymentOutput.validatedResources.Name
        $deploymentObj.OutputsString
        $deploymentName | % {
            $name = $_
            Write-Host "Deployment: $name" -ForegroundColor Green
            Get-AzureRMResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name $name | select -exp OutputsString
        }
    }
        
        
    }
