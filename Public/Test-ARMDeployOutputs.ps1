
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
    .Parameter DebugDeployment
    Uses test-azurermresourcegroupdeployment -debug:$true to return a json object of the deployment
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
            [string]$injectOutputTemplate,
            #Do not use global variable
            [switch]$doNotUseGlobal,
            [switch]$DebugDeployment
            )
          
        $ErrorActionPreference = 'Stop'
    
        #Check for $global:ArmDeploy
        if (!(Test-Path Variable:Global:armDeploy)) {
            New-Variable -Name armDeploy -Scope Global -Value @{Redeploy=$true}     
        }
        if ($doNotUseGlobal) {
            addToGlobal -key 'Redeploy' -value $false -force        
        }
    
        if ($Global:armDeploy.ContainsKey('resourceGroup') -and ($Global:armDeploy['Redeploy'] -eq $true)) {
            Write-Host "Using Global.armDeploy.resourceGroup"
            $rg=$Global:armDeploy.resourceGroup
        }
        else {
            Write-Host "Testing Azure resources..."
            try {
                success -message "Checking ResourceGroup $resourceGroupName in $resourceGroupLocation"
                $rg = Get-AzureRmResourceGroup  -Name $resourceGroupName -Location $resourceGroupLocation 
                addToGlobal -key 'resourceGroup' -value $rg
                success
    
            } catch { 
                success -failure
                $Global:armDeploy = $null
                $_;break
            } 
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
        
        if ($Global:armDeploy.containsKey('storageAccount') -and ($Global:armDeploy['Redeploy'] -eq $true)) {
            Write-Host "Using Global.armDeploy.storageAccount"
            $storageAccount=$Global:armDeploy.storageAccount
        }
        else {
            # Create a storage account name if none was provided
            if ($StorageAccountName -eq '') {
                $StorageAccountName = 'stage' + ((Get-AzureRmContext).Subscription.SubscriptionId).Replace('-', '').Replace('_','').substring(0, 19)
            }
            try {
                success -message "Checking storage account $storageaccountname"
                $StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})
                addToGlobal -key 'storageAccount' -value $StorageAccount
                success
            }
            catch {
                success -failure
                $Global:armDeploy = $null
                $_;break
            }
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
        if ($Global:armDeploy.ContainsKey('copyToStage') -and ($Global:armDeploy['Redeploy'] -eq $true)){
            Write-Host 'Using files already copied to staging directory'
            $ArtifactFilePaths = $Global:armDeploy.ArtifactFilePaths
            $stagePath = $Global:armDeploy.stagePath
        }
        else {
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
                
                addToGlobal -key 'copyToStage' -value $true
                $ArtifactFilePaths = (Get-ChildItem -Path $stagePath -File -Recurse -filter *.json) 
                addToGlobal -key 'ArtifactFilePaths' -value $ArtifactFilePaths  
                addToGlobal -key 'stagePath' -value $stagePath
            }
            catch  {
                success -failure
                $Global:armDeploy = $null
                $_;break        
            }  
        }
        #remove all resources from parent template
        if ($TemplateFile -Match $injectOutputTemplate) { 
            if ($Global:armDeploy.ContainsKey('templateFileCleared') -and ($Global:armDeploy['Redeploy'] -eq $true)){
                $templateFile = $Global:armDeploy.templateFileCleared
            }
            else {
                try { 
                    $templateFile = Join-Path $stagePath (Split-Path $templateFile -leaf)
                    success -message "Removing deployment resources from the parent template"        
                    clearResources -templateFiles $TemplateFile -allResources
                    success
    
                    addToGlobal -key 'templateFileCleared' -value $TemplateFile
                }
                catch {
                    success -failure
                    $Global:armDeploy = $null
                    $_;break
                }
            }
        }
        #removes all non resource.deployment resources from all templates
        else {
            #Get timestamp to retrieve deployments from linked templates
            $preDeployTimestamp = (Get-Date).ToUniversalTime()
            if ($Global:armDeploy.ContainsKey('resourcesCleared') -and ($Global:armDeploy['Redeploy'] -eq $true)){
                Write-Host 'All resources have been cleared'
            }
            else {
                try {            
                    success -message "Removing deployment resources from all templates"
                    clearResources $ArtifactFilePaths 
                    addToGlobal -Key 'resourcesCleared' -value $true
                    success
                }
                catch {
                    success -failure 
                    $_;break
                }
            } 
        }
        #inject output hashtable provided by user
        if (-not $varToOutput){        
            try {
                success -message "Injecting outputs in $injectOutputTemplate"
                $injectTemplate = (gci $stagepath -recurse | ? fullname -match $injectOutputTemplate)
                injectOutputs -templateFile $injectTemplate.FullName -outObj $injectOutput  
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
                $injectTemplate = $ArtifactFilePaths | ? Name -match $injectOutputTemplate 
                variableToOutput -templateFile $injectTemplate.FullName
                success
            }
            catch {
                success -failure 
                $_;break
            }
        }  
        #upload edited template files to container
        if ($Global:armDeploy.ContainsKey('injectOutputTemplate') -and ($Global:armDeploy['injectOutputTemplate'] -eq $injectOutputTemplate) -and ($Global:armDeploy['Redeploy'] -eq $true)) {   
            try {
                success -message "Uploading $($injectTemplate.name) from staging directory"
                Set-AzureStorageBlobContent -File $injectTemplate.FullName -Blob $injectTemplate.FullName.Substring($stagePath.length + 1) `
                                -Container $StorageContainerName -Context $StorageAccount.Context -Force | Out-Null
                success
            }
            catch {
                success -failure
                $Global:armDeploy = $null 
                $_;break  
            }
        }
        else { 
            foreach ($SourcePath in $ArtifactFilePaths.fullName) {
                try {
                    $name = Split-Path $SourcePath -Leaf
                    success -message "Uploading $name from staging directory"
                    Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($stagePath.length + 1) `
                                -Container $StorageContainerName -Context $StorageAccount.Context -Force | Out-Null
                    success
                    if ($name -eq $injectOutputTemplate) {
                        addToGlobal -key 'injectOutputTemplate' -value $name 
                    }
                }
                catch {
                    success -failure 
                    $Global:armDeploy = $null 
                    $_;break            
                }
            }
        }
        #point $templateFile to new azuredeploy-All.json
        $templateFile = Join-Path $stagePath (Split-Path $templateFile -leaf)
        #END Move templates to staging area and edit#
    
    
        # Begin deployment
        Write-Host "Starting Deployment..."
        $deploymentParams = @{
            Name = ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmmss'))
            ResourceGroupName = $ResourceGroupName
            TemplateFile = $TemplateFile 
            TemplateParameterFile = $TemplateParametersFile 
            Force = $true
            Verbose = $true
            ErrorVariable = 'ErrorMessages'
        }
        #If the params file includes _artifactsLocation, assume the other optional parameters are there and use them
        if ($JsonTemplateParameters.psobject.members.name -contains '_artifactsLocation'){
            $deploymentParams += $optionalParameters
            $deploymentObj =  New-AzureRmResourceGroupDeployment @deploymentParams 
        }
        else {
            $deploymentObj = New-AzureRmResourceGroupDeployment @deploymentParams
        }
        if ($ErrorMessages) {
            Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
            if( ($ErrorMessages.Exception | Get-Member -MemberType Property -Name Body) -ne $null )
            {
                Write-Output "Details"
                Write-Output ($ErrorMessages.Exception.Body.Details | ForEach-Object { ("{0}: {1}" -f $_.Code, $_.Message) } )
    
            }
            # Pass error messages regarding output Types to Get-CorrectTypes, and store them in a CSV
            if ($varToOutput) {
                Write-Host 'Trying to get correct output types...'                
                Get-CorrectTypes -ErrorMessages $ErrorMessages -csvPath (($injectTemplate.FullName).Replace('.json','.csv'))
            }
            addToGlobal -key 'Redeploy' -value $false
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
            addToGlobal -key 'Redeploy' -value $true 
            #Run a debug deployment
            if ($DebugDeployment) {
                $debugParams = @{
                    ResourceGroupName = $ResourceGroupName
                    TemplateFile = $TemplateFile 
                    TemplateParameterFile = $TemplateParametersFile 
                }
                if ($deploymentParams.keys -contains '_artifactsLocation') {
                    $debugParams+=$OptionalParameters
                }
                $debugPreference = 'Continue'
                try {
                    Success -Message "Starting Test Deployment"
                    
                    $rawResponse = Test-AzureRmResourceGroupDeployment @debugParams  -ErrorAction Stop 5>&1            
                    $deploymentOutput = (($rawResponse | Where-Object {$_ -like "*HTTP Response*"}) -split 'Body:' | Select-Object -Skip 1 | ConvertFrom-Json).properties                
                    success
                    addtoGlobal -key 'deploymentOutput' $deploymentOutput                
                    Write-Host "Added output to Armdeploy global variable."
                }
                catch {
                    Write-Host -foregroundcolor red 'Fail'
                    $_
                }  
                $debugPreference = 'SilentlyContinue'
            }   
        }  
    }
    