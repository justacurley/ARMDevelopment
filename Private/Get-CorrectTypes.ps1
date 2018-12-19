function Get-CorrectTypes
{
    [CmdletBinding()]
    param (
        [parameter(mandatory)]
        [array]$ErrorMessages,
        [parameter(mandatory = $false)]
        $csvPath
    )
    begin
    { 
        #Search the $matches index
        function get-indexOfMatch($allMatch, $Value)
        {
            $i = 0
            foreach ($item in $allMatch)
            {
                if ($item.value -eq $Value) { $i } 
                ++$i
            }
        }
    }
    process
    {
        $outputTypeError = $ErrorMessages.Exception | Where-Object {($_.Message -match '"code": "DeploymentOutputEvaluationFailed"') -and ($_.message -notmatch 'Microsoft.Resources/deployments')}
        if (!$outputTypeError)
        {            
            $outputTypeError = $ErrorMessages.Exception | Where-Object {($_.Message -match '"code": "DeploymentOutputEvaluationFailed"')}
            if (!$outputTypeError)
            {   
                throw 'Could not find output evaluation text'     
            }   
        }

        #The first match will be all of the output variables that threw errors.
        #Use that as a lookup. The match following the lookup will be the user provided type. Two matches later will be what Azure was expecting
        $outputTypeErrorPattern = "'[^']*'" 
        $outputAzureTypes = $outputTypeError.message | Select-String -Pattern $outputTypeErrorPattern -AllMatches
        $outputTypeIndex = $outputAzureTypes.matches[0].value.Replace("'", '').Split(',')  
        $correctTypeObject = foreach ($item in $outputTypeIndex)
        {
            $singleTics = "'{0}'" -f $item
            # "The template output 'emptyArray' is not valid:
            $instance = get-indexOfMatch -allMatch $outputAzureTypes.Matches -Value $singleTics            
            # This error would be at $instance+1 in allmatches ... Template output JToken type is not valid. Expected 'Object'
            # And this is what we're looking for ... Actual 'Array'.
            $correctType = $outputAzureTypes.Matches[($instance + 2)].value
            [PSCustomObject]@{
                variableName = $item
                variableType = $correctType.Replace("'",'')
            }
        }  

    }
    end
    {
        if ($csvPath)
        {
            #eventually will need more testing on the CSV file to remove possibly stale variable types 
            $correctTypeObject | Export-CSV -notypeinformation -Path $csvPath -NoClobber
        }
        else
        { 
            return $correctTypeObject
        }
    }
}
