$config = Get-Content -Raw -Path .\config\config.json | ConvertFrom-Json
Import-Module CredentialManager


function Main {
  $cookieContainer = New-Object System.Net.CookieContainer
  $handler = New-Object System.Net.Http.HttpClientHandler
  $handler.CookieContainer = $cookieContainer
  $handler.UseCookies = $true

  $handler.Credentials = New-AppCredential($config.UseCredentialManager)

  $c = New-Object System.Net.Http.HttpClient($handler)
  $c.DefaultRequestHeaders.Add("User-Agent", "PowerShell-HttpClient")

  Write-Host "`n[ Connecting to stmc.education.vic.gov.au... ]"
  $response = $c.GetAsync("https://stmc.education.vic.gov.au/stud_pwd").Result


  if (-not $response.IsSuccessStatusCode) {
    Write-Host "Request Failed: login"
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
  }

  Write-Host "[ Ok ]"


  Write-Host "`n[ Fetching the STMC student passwords landing page... ]"
  $response = $c.GetAsync("https://stmc.education.vic.gov.au/api/UserGet").Result

  if (-not $response.IsSuccessStatusCode) {
    Write-Host "Request Failed: stmc student passwords landing page"
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
  }

  Write-Host "[ Ok ]"

  $c.DefaultRequestHeaders.Add("emc-sch-id", ($config.SchooId))
  Write-Host "`n[ Fetching user data school id: $($config.SchooId)... ]"
  $response = $c.GetAsync("https://stmc.education.vic.gov.au/api/SchGetStuds?fullProps=true").Result

  if (-not $response.IsSuccessStatusCode) {
    Write-Host "Request Failed: stmc student user attributes page"
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
  }

  Write-Host "[ Ok ]"

  $responseBody = $response.Content.ReadAsStringAsync().Result

  $users = $responseBody | ConvertFrom-Json
  
  foreach ($u in $users) {
    Write-Output "DisplayName: $($u.disp), eduPassId: $($u.login), distinguishedName $($u.dn)"
  }

}

function New-AppCredential {
  param (
    [bool]$UseCredentialManager
  )

  if ($UseCredentialManager) {
    $cred = Get-StoredCredential -Target "stmc.education.vic.gov.au"
    $networkCredntial = New-Object System.Net.NetworkCredential(
      $cred.UserName,
      $cred.GetNetworkCredential().Password
    )

    return $networkCredntial
  }

  $username = $config.Credentials.user
  $password = $config.Credentials.password

  $pair = "$username`:$password"
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
  $encoded = [Convert]::ToBase64String($bytes)

  $networkCredntial = New-Object System.Net.NetworkCredential(
    $username,
    $password
  )

  return $networkCredntial
}



Main
