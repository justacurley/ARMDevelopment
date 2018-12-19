function copyToStage ($root,$additionalDir,$stagePath) {  

    if (!(test-path $stagePath)) { 
        New-Item -itemtype Directory -Path $stagePath -Force | Out-Null
    }

    try {
        Copy-Item $root\*.json -Destination $stagePath -Force -Recurse 
    }
    catch {$_}
     
    Foreach ($directory in $additionalDir) { 

        $additionalRoot = Get-ChildItem -Recurse -Directory -Filter $directory -Path $root -Verbose| select -exp fullname | where {$_ -notmatch "obj|Debug|bin\\Debug"} | select -first 1
        [string]$leaf = $additionalRoot.Replace($root,'')         
        $destPath = Join-Path -Path $stagePath -ChildPath $leaf

        if (!(test-path $destPath)) { 
            New-Item -itemtype Directory -Path $destPath -Force | Out-Null 
        }
        
        try { 
            Copy-Item -Path $additionalRoot\*.json -Destination $destPath -Force            
        }
        catch {$_} 
    }
} 