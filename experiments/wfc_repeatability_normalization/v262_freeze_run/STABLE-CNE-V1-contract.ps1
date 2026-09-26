Set-StrictMode -Version Latest

function Test-StableCneFresh {
    param(
        [Parameter(Mandatory=$true)][string]$BaselineRequest,
        [Parameter(Mandatory=$true)][string]$CurrentRequest
    )
    if($BaselineRequest -eq 'null'){return ($CurrentRequest -ne 'null')}
    return ($CurrentRequest -ne 'null' -and $CurrentRequest -ne $BaselineRequest)
}
