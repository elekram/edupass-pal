Import-Module CredentialManager

if (-not (Test-Path -Path '.\config\config.json' -PathType Leaf)) {
  Write-Host `n`n'Error: config.json file missing.'
  Write-Host "Create file './config/config.json'"
  Write-Host 'README: https://github.com/elekram/edupass-pal'`n
  Write-Host 'Script must exit'
  exit
}

$config = Get-Content -Raw -Path .\config\config.json | ConvertFrom-Json
$csvFile = $config.PasswordCsvFile
if (-not (Test-Path -Path ".\csv\$csvFile" -PathType Leaf)) {
  Write-Host `n`n'Error: student passwords CSV file missing'
  Write-Host "File name in config is '$csvFile' make sure './csv/$csvFile' exists"
  Write-Host 'Script must exit'`n`n
  exit
}

function Main {
  $client = New-AppHttpClient
  Open-StmcConnection -BaseUrl 'https://stmc.education.vic.gov.au/stud_pwd' -Client $client

  $studentPasswords = Get-PasswordsCsv
  $students = Get-StudentsFromStmc -Client $client

  foreach ($s in $students.GetEnumerator()) {
    $eduPassId = $s.Value.EduPassId

    if (-not $studentPasswords.ContainsKey($eduPassId)) {
      continue
    }

    $distinguishedName = $s.Value.DistinguishedName
    $studentDisplayName = $s.Value.DisplayName

    $tempPassword = New-RandomPassword

    Write-Host "`n-------"
    Write-Host "Processing student: $studentDisplayName`neduPassId: $eduPassId`nDistinguishedName $distinguishedName`n"

    $response = $null
    while (
      -not $response -or 
      -not $response.IsSuccessStatusCode
    ) {
      if ($null -ne $response) {
        Write-Host 'Retrying...'
      }

      Write-Host "SETTING TEMP PASSWORD: $tempPassword"
      $response = Set-EdupassIdPassword -DistinguishedName $distinguishedName -Secret $tempPassword -Client $client
      Write-Host "$([int]$response.StatusCode): $($response.StatusCode)"

      Start-Sleep -Seconds 1
    }
  }

  foreach ($s in $students.GetEnumerator()) {
    $eduPassId = $s.Value.EduPassId

    if (-not $studentPasswords.ContainsKey($eduPassId)) {
      continue
    }

    $schoolPassword = $studentPasswords[$eduPassId].Password
    
    $distinguishedName = $s.Value.DistinguishedName
    $studentDisplayName = $s.Value.DisplayName


    Write-Host '-------'
    Write-Host "Processing student: $studentDisplayName`neduPassId: $eduPassId`nDistinguishedName $distinguishedName`n" 
  
    $requestRetries = 0
    $response = $null
    while (
      -not $response -or 
      -not $response.IsSuccessStatusCode -and
      $requestRetries -lt 10
    ) {
      if ($null -ne $response) {
        Write-Host "`nRetrying..."
      }

      Write-Host "`nSETTING SCHOOL PASSWORD: $schoolPassword"
      $response = Set-EdupassIdPassword -DistinguishedName $distinguishedName -Secret $schoolPassword -Client $client
      Write-Host "$([int]$response.StatusCode): $($response.StatusCode)"

      Start-Sleep -Seconds 1
      $requestRetries++
    }
  }
  Write-Host "`n[ FINISHED - ALL PASSWORDS HAVE BEEN RESET ]"
}

function Set-EdupassIdPassword {
  param(
    [string]$DistinguishedName,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Secret,
    [System.Net.Http.HttpClient]$Client
  )

  $payload = @{
    dn     = $DistinguishedName
    newPwd = $Secret
  } | ConvertTo-Json -Depth 3

  Write-Host $payload

  $requestBody = New-Object System.Net.Http.StringContent(
    $payload,
    [System.Text.Encoding]::UTF8,
    'application/json'
  )

  $response = $Client.PostAsync(
    'https://stmc.education.vic.gov.au/api/StudResetPwd',
    $requestBody
  ).Result

  return $response
}

function  New-AppHttpClient {
  $cookieContainer = New-Object System.Net.CookieContainer
  $handler = New-Object System.Net.Http.HttpClientHandler
  $handler.CookieContainer = $cookieContainer
  $handler.UseCookies = $true

  $handler.Credentials = New-AppCredential($config.UseCredentialManager)

  $c = New-Object System.Net.Http.HttpClient($handler)
  $c.DefaultRequestHeaders.Add('User-Agent', 'PowerShell-HttpClient')

  return $c
}

function Get-StudentsFromStmc {
  param(
    [System.Net.Http.HttpClient]$Client
  )

  Write-Host "`n[ Fetching the STMC student passwords landing page... ]"
  $response = $Client.GetAsync('https://stmc.education.vic.gov.au/api/UserGet').Result

  if (-not $response.IsSuccessStatusCode) {
    Write-Host 'Request Failed: stmc student passwords landing page'
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
    Write-Host 'Script must exit.'
    exit
  }

  Write-Host '[ Fetched Ok ]'
  Write-Host "`n[ Fetching student data for school id: $($config.SchooId)... ]"

  $Client.DefaultRequestHeaders.Add('emc-sch-id', ($config.SchooId))
  $response = $Client.GetAsync('https://stmc.education.vic.gov.au/api/SchGetStuds?fullProps=true').Result

  if (-not $response.IsSuccessStatusCode) {
    Write-Host 'Request Failed: stmc student user attributes page'
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
    Write-Host 'Script must exit.'
    exit
  }

  Write-Host '[ Fetched Ok ]'

  $responseBody = $response.Content.ReadAsStringAsync().Result
  $departmentRecords = $responseBody | ConvertFrom-Json

  $students = New-Object 'System.Collections.Generic.Dictionary[string, object]'

  foreach ($r in $departmentRecords) {
    $eduPassId = $r.login
    $displayName = $r.disp
    $distinguishedName = $r.dn

    if ([string]::IsNullOrWhiteSpace($eduPassId)) {
      continue
    }
 
    if ([string]::IsNullOrWhiteSpace($distinguishedName)) {
      continue
    }

    $student = [PSCustomObject]@{
      EduPassId         = $eduPassId.ToUpper()
      DisplayName       = $displayName
      DistinguishedName = $distinguishedName
    }  

    $students.Add($eduPassId.ToUpper(), $student)
  }

  return $students
}

function New-AppCredential {
  param (
    [bool]$UseCredentialManager
  )

  if ($UseCredentialManager) {
    $cred = Get-StoredCredential -Target $config.SiteUrl
    $networkCredntial = New-Object System.Net.NetworkCredential(
      $cred.UserName,
      $cred.GetNetworkCredential().Password
    )

    return $networkCredntial
  }

  $username = $config.Credentials.user
  $password = $config.Credentials.password

  $networkCredntial = New-Object System.Net.NetworkCredential(
    $username,
    $password
  )

  return $networkCredntial
}

function Open-StmcConnection {
  param(
    [string]$BaseUrl,
    [System.Net.Http.HttpClient]$Client
  )

  Write-Host "`n[ Connecting to stmc.education.vic.gov.au... ]"

  $response = $Client.GetAsync($BaseUrl).Result
  $requestRetries = 0

  while (
    -not $response -or 
    -not $response.IsSuccessStatusCode -and 
    $requestRetries -ne 5
  ) {

    $requestRetries++ 
    if ($requestRetries -eq 5) {
      Write-Host 'Too many retries. Exiting'
      exit
    }

    Write-Host 'Request Failed: login'
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
    Write-Host 'Retrying...'

    Start-Sleep -Seconds 2
    LoginToStmc($client)
  }

  Write-Host '[ Connected Ok ]'
}

function New-RandomPassword {
  $randNumbers1 = Get-Random -Minimum 100 -Maximum 999
  $randNumbers2 = Get-Random -Minimum 100 -Maximum 999

  $randLetters1 = Get-RandomLetters
  $randLetters2 = Get-randomLetters
  $randUpperCaseLetter = $randLetters2.ToUpper()

  $characters = @('!', '@', '#', '$', '%', '^')
  $randCharacter = Get-Random -InputObject $characters

  $pword = "$randLetters1$randNumbers1$randUpperCaseLetter$randNumbers2$randCharacter"
  
  return $pword
}

function Get-RandomLetters {
  $randomLetters = $( -join ((65..90) + (97..122) | 
      Get-Random -Count 3 | 
      ForEach-Object { [char]$_ })).ToString().ToLower()
  return $randomLetters
}

function Get-PasswordsCsv {
  $csvFileName = $config.PasswordCsvFile
  $passwordsCSV = Import-Csv -Path  ".\csv\$csvFileName"

  $dict = New-Object 'System.Collections.Generic.Dictionary[string, object]'

  foreach ($row in $passwordsCSV) {
    $eduPassId = $row.login
    $password = $row.password

    if (!$password) { 
      continue
    }

    if (-not [string]::IsNullOrWhiteSpace($eduPassId)) {
      $student = [PSCustomObject]@{
        Password = $password
      }  

      $dict.Add($eduPassId, $student)
    }
  }

  return $dict

}

Main
