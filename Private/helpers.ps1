# https://stackoverflow.com/questions/25682507/powershell-inline-if-iif
# Helper method to handle inline if's
# Avoids evaluation of both $IfTrue and $IfFalse parameters
# Example (Simple): iif ($ifpart) $true $false
# Example (Complex): $VolatileEnvironment = Get-Item -ErrorAction SilentlyContinue "HKCU:\Volatile Environment"
#                    $UserName = IIf $VolatileEnvironment {$_.GetValue("UserName")}
Function IIf($If, $IfTrue, $IfFalse) {
    If ($If -IsNot "Boolean") {$_ = $If}
    If ($If) {If ($IfTrue -is "ScriptBlock") {&$IfTrue} Else {$IfTrue}}
    Else {If ($IfFalse -is "ScriptBlock") {&$IfFalse} Else {$IfFalse}}
}

function success ($message,[switch]$failure) {
    if ($message) {
      Write-Host " " -NoNewline
      Write-Host "$message..." -ForegroundColor "Gray" -NoNewline
    }
    elseif ($failure){
        Write-Host "X" -ForegroundColor "Red"
    }
    else {
      Write-Host $([Char]8730) -ForegroundColor "Green"
    }
  }

  function Format-ValidationOutput {
    param ($ValidationOutput, [int] $Depth = 0)
    Set-StrictMode -Off
    return @($ValidationOutput | Where-Object { $_ -ne $null } | ForEach-Object { @('  ' * $Depth + ': ' + $_.Message) + @(Format-ValidationOutput @($_.Details) ($Depth + 1)) })
}