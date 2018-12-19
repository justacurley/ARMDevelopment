
function testJson {
    param (
        $file
    )
    $template = (get-content $file) | % {$_ -replace '\s\/\/.*', '' | ? {$_.trim() -ne "" }} | Out-String
    $filename = $file.Split("\")[-1]
    try {
        Write-Host "Attempting to convert $filename from Json..." -NoNewline
        $template | ConvertFrom-Json | Out-Null
        Write-Host "Success"
    }
    catch  {
        Write-Host "Fail" -ForegroundColor Yellow
        $pattern = "\(\d+\)"
        $arrError=$_.exception.message.split("`n`r")
        Write-Warning $arrError[0]
        try {
        [int]$substring = ($arrError[0] | select-string -Pattern $pattern).matches.Value.Replace('(','').Replace(')','')
        $item = $_.exception.message.Substring(($substring)).split("`n`r") 
        Write-Output ($item | select -first 10)    
        }
        catch{}
    }
}

