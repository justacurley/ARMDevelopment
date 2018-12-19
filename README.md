# ARMDevelopment
A module for faster ARM template testing and debugging. 

I've been creating large, complex arm templates for a year now, and always lamented having to debug them. I have three sets of templates:
  - A blank template to test simple functions
  - A copy of 'production' templates with all the resources removed to test variables/parameters between linked templates
  - The 'production' templates I deploy with

I got tired of keeping my copy up to date, and the slim usefulness of the blank template, so I made this PS module. The real beauty here is being able to test variables, parameters, and functions as data is passed through linked templates.


# cmdlets
  - Test-ArmDeployOutputs
  - Build-Outputs

<b>Test-ArmDeployOutputs</b> is the meat of the operation. Provide it some standard azure deployment parameters (ResourceGroup,StorageAccount,TemplateFile,ParamsFile, etc) and what you would like injected into the Outputs {} section of the template you specify.  

The cmdlet will copy all your templates to a directory in $env:temp, remove the resources[] from the templates (so we dont deploy anything on accident), inject a hashtable of outputs, upload, and deploy.

<b>Build-Outputs</b> sets up in a similar way. Provide it some standard parameters plus templatefile. This cmdlet will take all the variables from the templatefile you specify, and attempt to inject them as outputs using some ***voodoo*** that doesn't work very well.

# Ex.
Lets take one variables from this quickstart template and inject it as an output  
```powershell
$modulePath = 'C:\Users\JustACurley\Source\Modules\ARMDevelopment'  
Import-Module $modulePath -Force 

$branchRoot = 'C:\Users\JustACurley\Source\azure-quickstart-templates\101-1vm-2nics-2subnets-1vnet'
$outputParams = @{
    rootPath               = $branchRoot
    templateFile           = '{0}\azuredeploy.json' -f $branchRoot  
    templateParametersFile = '{0}\azuredeploy.parameters.json' -f $branchRoot
    resourceGroupName      = 'templateautomation-sandbox'    
    resourceGroupLocation  = 'eastus2'
    storageAccountName     = 'sainfrasbuse01'
    injectOutputTemplate   = 'azuredeploy.json' 
}
$testFunc2 = @'
[variables('diagStorageAccountName')]
'@
$injectOutput = @{
    'testFunc2' = @{
        value = $testFunc2
        type  = 'string'
    }
}
Test-ArmDeployOutputs @outputParams -injectOutput $injectOutput -OutVariable foo
```
The result looks like this: 
``` 
Deployment: azuredeploy-1219-0041

Name             Type                       Value
===============  =========================  ==========
testFunc2        String                     diags5xevxe74cfmus
```

Using the same template, this is what the -varToOutput switch looks like  
![varToOutput](https://github.com/justacurley/ARMDevelopment/blob/master/varToOutput.png)

# ToDo
  - Add cmdlet specifically for Test-AzureRMResourcegroupDeployment -Debug
  - Clean up File/Folder parameters so they're all in line and make sense
  




