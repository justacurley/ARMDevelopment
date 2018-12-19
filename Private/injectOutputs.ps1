function injectOutputs($templateFile,$outObj) {    
            #convert json string to pscustomobject   
            try {
                $templateObj = (get-content $templateFile) | % {$_ -replace '\s\/\/.*', ''} | Out-String | convertFrom-Json -ErrorAction Stop
            }
            catch {
                #Make a poor attempt at figuring out the issue
                testJson $templateFile
                break
            }                                
            
            $templateObj.outputs = $outObj
            #convert back to json string and overwrite file
            $templateObj | ConvertTo-Json -depth 99 | foreach {$_ -replace '\\u0027', "'"} | Out-File $templateFile -Force
}