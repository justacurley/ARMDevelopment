
function Test-ARMDeployOutputs { 
    <#
    .Synopsis
    Quickly test ARM functions by injecting them as outputs in template files
    .Description
    This command will copy templates to a temp directory, remove all resources[] that are not nested/linked deployments, and inject a user provided hashtable into the 
    Outputs section of the specified template. This workflow speeds up testing/debugging ARM functions.
    .Parameter StorageContainerName
    Specify a storage container name, or "dynamically" create one that will look something like resourcegroupname-username-stageartifacts
    .Parameter RootPath
    The top level directory of the repo which contains the parent json template
    .Parameter TemplateFile
    The full path to the template file 
    .Parameter TemplateParametersFile
    The full path to the template params file
    .Parameter additionalTemplateDirectories
    The folder name(s) which contain linked templates. This isn't needed if you are deploying from the parent template only.
    .Parameter OptionalParameters
    Optional parameters for your template. Usually _artifactsLocation and _artifactsLocationSASToken
    .Parameter injectOutput
    Hashtable of outputs to inject in either the parent or a linked template
    .Parameter injectOutputTemplate
    The name of the template injectOutput will be placed in
    .Parameter varToOutput
    Convert all variables in parent template (or injectOutputTemplate, if specified) to Outputs
    .Example
    Inject the variable 'diagStorageAccountName' as an output in 'C:\Users\JustACurley\azure-quickstart-templates\101-1vm-2nics-2subnets-1vnet\azuredeploy.json'
    PS C:\> $branchRoot = 'C:\Users\JustACurley\azure-quickstart-templates\101-1vm-2nics-2subnets-1vnet'
    PS C:\> $outputParams = @{
            rootPath               = $branchRoot
            templateFile           = '{0}\azuredeploy.json' -f $branchRoot  
            templateParametersFile = '{0}\azuredeploy.parameters.json' -f $branchRoot
            resourceGroupName      = 'rg-templateautomation-sandbox'
            resourceGroupLocation  = 'eastus2'
            storageAccountName     = 'sainfrasbuse201'
            }
    PS C:\> $testFunc = @'
            [variables('diagStorageAccountName')]
            '@
    PS C:\> $injectOutput = @{
            'testFunc'  = @{ 
                value = $testFunc
                type  = 'string'
            }
    PS C:\> Test-ArmDeployOutputs @outputParams -injectOutput $injectOutput
    .Example
    Convert all variables in azuredeploy.json and inject them as outputs
    PS C:\> $branchRoot = 'C:\Users\JustACurley\azure-quickstart-templates\101-1vm-2nics-2subnets-1vnet'
    PS C:\> $outputParams = @{
            rootPath               = $branchRoot
            templateFile           = '{0}\azuredeploy.json' -f $branchRoot  
            templateParametersFile = '{0}\azuredeploy.parameters.json' -f $branchRoot
            resourceGroupName      = 'rg-templateautomation-sandbox'
            resourceGroupLocation  = 'eastus2'
            storageAccountName     = 'sainfrasbuse201'
            }
    PS C:\> Test-ArmDeployOutputs @outputParams -varToOutput
    .Link
    https://github.com/justacurley/ARMDevelopment
    #>
        [cmdletbinding()]
        Param(
            [parameter(Mandatory)]
            [validateSet("eastasia","southeastasia","centralus","eastus","eastus2","westus","northcentralus","southcentralus","northeurope","westeurope","japanwest","japaneast","brazilsouth","australiaeast","australiasoutheast","southindia","centralindia","westindia","canadacentral","canadaeast","uksouth","ukwest","westcentralus","westus2","koreacentral","koreasouth","francecentral","francesouth","australiacentral","australiacentral2")]
            [string] $ResourceGroupLocation,
            [parameter(Mandatory)]
            [string] $ResourceGroupName,
            [parameter(Mandatory)]
            [string] $StorageAccountName,
            #build user-unique container name name
            [parameter(Mandatory=$false)]
            [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant().Replace('_','') + '-' + ($env:username).tolower().replace('adm-','').replace('_','').replace('.','') + '-stageartifacts',
            #Full Path to root of repo (should contain parent template)
            [parameter(Mandatory)]
            [ValidateScript({validatePath $_})] 
            [System.IO.FileInfo] $RootPath,
            #Full Path to parent template file
            [parameter(Mandatory)] 
            [ValidateScript({validatePath $_})]        
            [System.IO.FileInfo] $TemplateFile,
            #Full Path to parameters file
            [parameter(Mandatory)]
            [ValidateScript({validatePath $_})] 
            [System.IO.FileInfo] $TemplateParametersFile,
            #Directories that contain template files (ex. Linked Templates)
            [parameter(Mandatory=$false)]        
            [string[]] $additionalTemplateDirectories,
            #used for deployment purposes --- optional param
            [hashtable] $OptionalParameters = $null, 
            #Hashtable with outputs to be injected/tested
            [hashtable]$injectOutput,
            #Converts variables to hashtable of outputs
            [switch]$varToOutput,  
            #Template name to inject $injectOutput into      
            [parameter(mandatory)]
            [string]$injectOutputTemplate
            )
          
        $ErrorActionPreference = 'Stop'
        Write-Host "Testing Azure resources..."
        try {
            success -message "Checking ResourceGroup $resourceGroupName in $resourceGroupLocation"
            $rg = Get-AzureRmResourceGroup  -Name $resourceGroupName -Location $resourceGroupLocation 
            success
    
        } catch { 
            success -failure
            $_;break
        } 
    
        $rootPath = (Get-Item $rootPath).FullName 
        
        ######################################
        #Set up storage account/container/sas#
        ######################################
        if( $OptionalParameters -eq $null ) 
        {
            $OptionalParameters = New-Object -TypeName Hashtable
        }   
        # Add the folder path to the json parameters file so that the PSD files used in DSC can be found without adding another parameter into the parameters file
        $parametersDirectory = (Split-Path -Path $templateParametersFile)     
        # Inject the parameter into the deployment
        $OptionalParameters['_parametersDirectory'] = $parametersDirectory
        Write-Host "Clean templates and upload artifacts..." 
        # Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
        $JsonParameters = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
        if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
            $JsonParameters = $JsonParameters.parameters
        }    
        $JsonTemplateParameters = Get-Content $TemplateFile -Raw | ConvertFrom-Json
        if (($JsonTemplateParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
            $JsonTemplateParameters = $JsonTemplateParameters.parameters
        }  
        $ArtifactsLocationName = '_artifactsLocation'
        $ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'
        $OptionalParameters[$ArtifactsLocationName] = $JsonParameters | Select -Expand $ArtifactsLocationName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore
        $OptionalParameters[$ArtifactsLocationSasTokenName] = $JsonParameters | Select -Expand $ArtifactsLocationSasTokenName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore
        
        # Create a storage account name if none was provided
        if ($StorageAccountName -eq '') {
            $StorageAccountName = 'stage' + ((Get-AzureRmContext).Subscription.SubscriptionId).Replace('-', '').Replace('_','').substring(0, 19)
        }
        try {
            success -message "Checking storage account $storageaccountname"
            $StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})
            success
        }
        catch {
            success -failure
            $_;break
        }
      
        # Generate the value for artifacts location if it is not provided in the parameter file
        if ($OptionalParameters[$ArtifactsLocationName] -eq $null) {
            $OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
        }    
        # Copy files from the local storage staging location to the storage account container    
        New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
    
        # Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
        if ($OptionalParameters[$ArtifactsLocationSasTokenName] -eq $null) {
            $OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString -AsPlainText -Force `
                (New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
        } 
        #END Set up storage account/container/sas#
    
        #########################################
        #Move templates to staging area and edit#
        #########################################
        #Create a temp path for templates, this will become the rootpath for the rest of the script
        $stagePath = join-path ([system.io.path]::GetFullPath($env:temp)) -childPath $storageContainerName     
        #copy all template files to $env:temp 
        try {
            $copyToStageParams = @{
                root = $RootPath
                stagePath = $stagePath
            }
            #If user provided linked template directories, copy them as well
            if ($additionalTemplateDirectories) {
                $copyToStageParams.Add('additionalDir',$additionalTemplateDirectories)
            }
            success -message "Copying templates from $rootPath to $stagepath"        
            copytoStage @copyToStageParams
            success
            $ArtifactFilePaths = (Get-ChildItem -Path $stagePath -File -Recurse -filter *.json)   
        }
        catch  {
            success -failure
            $_;break        
        }  
        #remove all resources from parent template
        if ($TemplateFile -Match $injectOutputTemplate) { 
            try { 
                $templateFile = Join-Path $stagePath (Split-Path $templateFile -leaf)
                success -message "Removing deployment resources from the parent template"        
                clearResources -templateFiles $TemplateFile -allResources
                success
            }
            catch {
                success -failure
                $_;break
            }
        }
        #removes all non resource.deployment resources from all templates
        else {
            #Get timestamp to retrieve deployments from linked templates
            $preDeployTimestamp = (Get-Date).ToUniversalTime()
            try {            
                success -message "Removing deployment resources from all templates"
                clearResources $ArtifactFilePaths 
                success
            }
            catch {
                success -failure 
                $_;break
            }
        }
        #inject output hashtable provided by user
        if (-not $varToOutput){
            try {
                success -message "Injecting outputs in $injectOutputTemplate"
                $injectTemplate = (gci $stagepath -recurse | ? fullname -match $injectOutputTemplate).fullname
                injectOutputs -templateFile $injectTemplate -outObj $injectOutput  
                success
            }
            catch {
                success -failure 
                $_;break
            }
        }
        #convert all variables in template to outputs
        else {
            try {
                success -message "Converting all variables in $injectOutputTemplate to Outputs"
                $filePath = $ArtifactFilePaths | ? Name -match $injectOutputTemplate 
                variableToOutput -templateFile $filePath.FullName
                success
            }
            catch {
                success -failure 
                $_;break
            }
        }  
        #upload edited template files to container    
        foreach ($SourcePath in $ArtifactFilePaths.fullName) {
            try {
                $name = Split-Path $SourcePath -Leaf
                success -message "Uploading $name from staging directory"
                Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($stagePath.length + 1) `
                            -Container $StorageContainerName -Context $StorageAccount.Context -Force | Out-Null
                success
            }
            catch {
                success -failure 
                $_;break            
            }
        }
        #point $templateFile to new azuredeploy-All.json
        $templateFile = Join-Path $stagePath (Split-Path $templateFile -leaf)
        #END Move templates to staging area and edit#
    
    
        # Begin deployment
        Write-Host "Starting Deployment..."
        $deploymentParams = @{
            Name = ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))
            ResourceGroupName = $ResourceGroupName
            TemplateFile = $TemplateFile 
            TemplateParameterFile = $TemplateParametersFile 
            Force = $true
            Verbose = $true
            ErrorVariable = 'ErrorMessages'
        }
        #If the template file includes _artifactsLocation, assume the other optional parameters are there and use them
        if ($JsonTemplateParameters.psobject.members.name -contains '_artifactsLocation'){
            $deploymentObj =  New-AzureRmResourceGroupDeployment @deploymentParams @optionalParameters
        }
        else {
            $deploymentObj = New-AzureRmResourceGroupDeployment @deploymentParams
        }
        if ($ErrorMessages) {
            Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
            if( $ErrorMessages.Exception.Body -ne $null )
            {
                Write-Output "Details"
                Write-Output ($ErrorMessages.Exception.Body.Details | ForEach-Object { ("{0}: {1}" -f $_.Code, $_.Message) } )
    
            }
            # Pass error messages regarding output Types to Get-CorrectTypes, and store them in a CSV
            if ($varToOutput) {
                Write-Host 'Trying to get correct output types...'                
                Get-CorrectTypes -ErrorMessages $ErrorMessages -csvPath (($filePath.FullName).Replace('.json','.csv'))
            }
        }
        else { 
            Write-Host "Deployment successfull, checking for Outputs"        
            #Outputs from linked templates
            if ($TemplateFile -NotMatch $injectOutputTemplate) { 
                $deployments = Get-AzureRMResourceGroupDeployment -ResourceGroupName $resourceGroupName | Where-Object { ($_.Timestamp -gt $preDeployTimestamp) -and ($_.OutputsString -ne '')}
                foreach ($deployment in $deployments) {
                    $name = $deployment.deploymentName
                    Write-Host "Deployment: $name" -ForegroundColor Green
                    $deployment.OutputsString
                }
            }
            #Outputs from the parent template
            else {
                $name = $deploymentObj.DeploymentName
                Write-Host "Deployment: $name" -ForegroundColor Green            
                $deploymentObj.OutputsString
            }    
        }  
    }
    