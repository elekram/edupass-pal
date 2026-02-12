Import-Module CredentialManager
$config = Get-Content -Raw -Path .\config\config.json | ConvertFrom-Json

function Main {
  $client = New-AppHttpClient
  $client = LoginToStmc -BaseUrl 'https://stmc.education.vic.gov.au/stud_pwd' -Client $client

  $students = Get-StudentsFromStmc($client)

  $connectionString = $config.SQL.Server + $config.SQL.Catalog + $config.SQL.UserId + $config.SQL.Password 
  $tableName = $config.SQL.TableName
  $studentPasswords = Get-StudentDbPasswords -ConnectionString $connectionString -TableName $tableName
  
  foreach ($s in $students) {
    $eduPassId = $s.login
    $distringuisedName = $s.dn

    if ($studentPasswords.ContainsKey($eduPassId)) {
      if ($studentPasswords[$eduPassId].RemotePasswordSet) {
        Write-Host 'IS SET'
      }
      else {
        Write-Host 'NULL AND NOT SET'
      }
    }

    
    if ($studentPasswords.ContainsKey($eduPassId)) {
      $payloadWithRandomPassword = @{
        dn     = $distringuisedName
        newPwd = New-RandomPassword
      } | ConvertTo-Json -Depth 3

      $payloadWithRecordedPassword = @{
        dn     = $distringuisedName
        newPwd = $studentPasswords[$eduPassId].Password
      } | ConvertTo-Json -Depth 3


      Write-Host $payloadWithRandomPassword
      Write-Host $payloadWithRecordedPassword

      Write-Output "DisplayName: $($s.disp), eduPassId: $($s.login), distinguishedName $($s.dn), password $($studentPasswords[$s.login].Password)" 


      $requestBody = New-Object System.Net.Http.StringContent(
        $payloadWithRandomPassword,
        [System.Text.Encoding]::UTF8,
        'application/json'
      )

      $response = $client.PostAsync(
        'https://stmc.education.vic.gov.au/api/StudResetPwd',
        $requestBody
      ).Result

      Write-Host $response

      Start-Sleep -Seconds 5


      $requestBody = New-Object System.Net.Http.StringContent(
        $payloadWithRecordedPassword,
        [System.Text.Encoding]::UTF8,
        'application/json'
      )

      $response = $client.PostAsync(
        'https://stmc.education.vic.gov.au/api/StudResetPwd',
        $requestBody
      ).Result

      Write-Host $response

    }
    return
  }
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

function Get-StudentsFromStmc($client) {
  Write-Host "`n[ Fetching the STMC student passwords landing page... ]"

  $response = $client.GetAsync('https://stmc.education.vic.gov.au/api/UserGet').Result

  if (-not $response.IsSuccessStatusCode) {
    Write-Host 'Request Failed: stmc student passwords landing page'
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
    Write-Host 'Script must exit.'
    exit
  }

  Write-Host '[ Fetched Ok ]'
  Write-Host "`n[ Fetching student data for school id: $($config.SchooId)... ]"

  $client.DefaultRequestHeaders.Add('emc-sch-id', ($config.SchooId))
  $response = $client.GetAsync('https://stmc.education.vic.gov.au/api/SchGetStuds?fullProps=true').Result

  if (-not $response.IsSuccessStatusCode) {
    Write-Host 'Request Failed: stmc student user attributes page'
    Write-Host ($response.StatusCode)
    Write-Host ([int]$response.StatusCode)
    Write-Host 'Script must exit.'
    exit
  }

  Write-Host '[ Fetched Ok ]'

  $responseBody = $response.Content.ReadAsStringAsync().Result

  $students = $responseBody | ConvertFrom-Json
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

function LoginToStmc {
  param(
    [string]$BaseUrl,
    [System.Net.Http.HttpClient]$Client
  )
  Write-Host "`n[ Connecting to stmc.education.vic.gov.au... ]"

  $response = $client.GetAsync($BaseUrl).Result
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
  return $client
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

function Get-RandomLetters() {
  $randomLetters = $( -join ((65..90) + (97..122) | 
      Get-Random -Count 3 | 
      ForEach-Object { [char]$_ })).ToString().ToLower()
  return $randomLetters
}

function Get-StudentDbPasswords {
  param(
    [string]$ConnectionString,
    [string]$TableName
  )

  $connection = New-Object System.Data.SqlClient.SQLConnection($ConnectionString)

  $lookupQuery = "
  SELECT [StudentCode], [Password], [eduPassId], [remotePasswordSet] 
    FROM $TableName"

  $connection.Open()
  $command = New-Object System.Data.SqlClient.SqlCommand($lookupQuery, $connection);

  $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
  $dataTable = New-Object System.Data.DataTable
  $adapter.Fill($dataTable) | Out-Null

  $connection.Close()

  $dict = New-Object 'System.Collections.Generic.Dictionary[string,object]'

  foreach ($row in $dataTable.Rows) {
    
    $eduPassId = $row['eduPassId']

    if (-not [string]::IsNullOrWhiteSpace($eduPassId)) {
      $student = [PSCustomObject]@{
        StudentCode       = $row['StudentCode'].ToString()
        Password          = $row['Password'].ToString()
        RemotePasswordSet = [bool]$row['remotePasswordSet']
      }  

      $dict.Add($eduPassId, $student)
    }
  }

  return $dict
}

function Set-StudentPasswordUpdated {
  param(
    [string]$ConnectionString,
    [string]$TableName,
    [string]$EdupassId
  )

  $connection = New-Object System.Data.SqlClient.SQLConnection($ConnectionString)

  $connection.Open()
  $command = New-Object System.Data.SQLClient.SQLCommand
  $command.Connection = $connection
  
  $cmd = "UPDATE $TableName
    SET [RemotePasswordSet] = $true
    WHERE [eduPassId] = '$EdupassId'"
  

  $command.CommandText = $cmd
  $sqlResponse = $command.ExecuteNonQuery()
  $connection.Close()

  return $sqlResponse
}

Main
