Set-StrictMode -Version 3

$script:session = $null

# Load public functions
$publicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public" -Recurse -Include *.ps1 -Exclude *.tests.ps1
foreach ($function in $publicFunctions) {
    . $function.FullName
}

# Load private functions
$privateFunctions = Get-ChildItem -Path "$PSScriptRoot\Private" -Recurse -Include *.ps1 -Exclude *.tests.ps1
foreach ($function in $privateFunctions) {
    . $function.FullName
}

#Export-ModuleMember -Function *
