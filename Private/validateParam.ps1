function validatePath ($path) {
    if( -Not ($path | Test-Path) ){
        throw "File or folder does not exist"
    }
    else {
        return $true
    }
}