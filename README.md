# Edupass-Pal

## Example required config.json that needs to be placed in a folder named 'config' in the root of the project.
- To use Windows Credential manager, use the Windows Credentials store and then 'Add a Generic Credential'.
- The CredentialManager cmdlets/module can be installed from the PowerShell Gallery 
- If you wish to store your username and password in the config.json set UseCredentialManager to false.

## Password CSV file matches the STCM template which has a two columns and a headers. See the example below. 

```json
{
  "SiteUrl": "stmc.education.vic.gov.au",
  "SchooId": "0000",
  "PasswordCsvFile": "sample_stud_pwd_reset.csv",
  "UseCredentialManager": true,
  "Credentials": {
    "user": "mark.lee@education.vic.gov.au",
    "password": ""
  }
} 
```

## Example CSV file
```csv
login,password
user1,Welcome.1
user2,Welcome.2
user3,Welcome.3
```