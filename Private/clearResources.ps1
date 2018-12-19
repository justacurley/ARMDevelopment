function clearResources($templateFiles,[switch]$allResources) {
    foreach ($template in $templateFiles) { 
        
            #convert json string to pscustomobject    
            try {
                $templateObj = (get-content $template.fullName) | % {$_ -replace '\s\/\/.*', ''} | Out-String | convertFrom-Json -ErrorAction Stop
            }
            catch {
                #Make a poor attempt at figuring out the issue
                testJson $template.fullName
                break
            }                                
            
            if ($allResources){
                ($templateObj.psobject.members | ? name -eq resources).value = @()
            }
            else {
                #clear out all non-deployment resources from template
                $deploymentResources = ($templateObj.psobject.members | ? name -eq resources).value | ? type -eq 'Microsoft.Resources/deployments'
                ($templateObj.psobject.members | ? name -eq resources).value = @($deploymentResources)
            }
            #convert back to json string and overwrite file
            $templateObj | ConvertTo-Json -depth 99 | foreach {$_ -replace '\\u0027', "'"} | Out-File $template.FullName -Force
    }
}