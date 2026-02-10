$config = Get-Content -Raw -Path .\config\config.json | ConvertFrom-Json



function Main {
  $username = $config.Credentials.user
  $password = $config.Credentials.password

  $pair = "$username`:$password"
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
  $encoded = [Convert]::ToBase64String($bytes)
  

  $cookieContainer = New-Object System.Net.CookieContainer
  $handler = New-Object System.Net.Http.HttpClientHandler
  $handler.CookieContainer = $cookieContainer
  $handler.UseCookies = $true

  $handler.Credentials = New-Object System.Net.NetworkCredential(
    $username,
    $password
  )

  $c = New-Object System.Net.Http.HttpClient($handler)
  $c.DefaultRequestHeaders.Add("User-Agent", "PowerShell-HttpClient")

  Write-Host "Connecting to stmc.education.vic.gov.au..."
  $response = $c.GetAsync("https://stmc.education.vic.gov.au/stud_pwd").Result


  if (-not $response.IsSuccessStatusCode) {
    Write-Host "Request Failed: login"
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
  }

  Write-Host "Ok"


  Write-Host "Connecting to stmc student passwords landing page"
  $response = $c.GetAsync("https://stmc.education.vic.gov.au/api/UserGet").Result

  if (-not $response.IsSuccessStatusCode) {
    Write-Host "Request Failed: stmc student passwords landing page"
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
  }

  Write-Host "Ok"

  $c.DefaultRequestHeaders.Add("emc-sch-id", ($config.SchooId))
  Write-Host "Connecting to stmc student user attributes page for ($config.SchoolId)"
  $response = $c.GetAsync("https://stmc.education.vic.gov.au/api/SchGetStuds?fullProps=true").Result

  if (-not $response.IsSuccessStatusCode) {
    Write-Host "Request Failed: stmc student user attributes page"
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
  }
}


Main
