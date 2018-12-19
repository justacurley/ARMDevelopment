function PSTypeToJSON($psType)
{
    switch ($psType)
    {
        'System.String' { 'string' }
        'System.Object[]' { 'object' }
        'System.Array[]' { 'array' }
        Default {'string'}
    }
}

function getType($csvFile, $name)
{
    try
    {
        $types = Import-CSV -Path $csvFile -ErrorAction Stop
    }
    catch {$_}
    $correctType = ($types | ? variableName -match $name ).variableType
    return $correctType
}

#$templateFile is FullName/full path
function variableToOutput($templateFile)
{
    #convert json string to pscustomobject                                   
    $templateObj = (get-content $templateFile) | % {$_ -replace '\s\/\/.*', ''} | Out-String | convertFrom-Json

    #If CSV of variable types for this template already exists, import it 
    $csvFile = $templateFile.replace('.json', '.csv')
    if (test-path $csvFile)
    {
        $types = Import-Csv -Path $csvFile
    }  
    else {
        $types = @{
            variableName=$null
            variableType=$null
        } 
    }   
            
    ($templateObj.variables.psobject.members | ? membertype -eq noteproperty)| % {
        $name = $_.name
        $value = "[variables('{0}')]" -f $name 
        #Check CSV for type, else make a best guess with the psobject typeName
        if (($types | ? variableName -eq $name) -ne $null)
        {                    
            $Type = ($types | ? variableName -eq $name).variableType
        }
        else
        {
            $Type = (PSTypeToJSON $_.TypeNameOfValue)
        }
             
        $hashtable = @{}
        $hashtable.add('type', $type)
        $hashtable.add('value', $value)
        $templateObj.outputs | Add-Member NoteProperty $name $hashtable
    }    
    # convert back to json string and overwrite file
    $templateObj | ConvertTo-Json -depth 99 | foreach {$_ -replace '\\u0027', "'"} | Out-File $templateFile -Force    
}

