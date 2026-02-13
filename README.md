# Edupass-Pal

## Example required config.json that needs to e placed in a folder named 'config' in the root of the project.
```json
{
  "SiteUrl": "stmc.education.vic.gov.au",
  "SchooId": "0000",
  "SQL": {
    "Server": "server=svr;",
    "TableName": "[dbo].[SomeTable]",
    "Catalog": "initial catalog=somecatalog;",
    "UserId": "uid=someuser;",
    "Password": "pwd=secret;"
  },
  "UseCredentialManager": true,
  "Credentials": {
    "user": "mark.lee@education.vic.gov.au",
    "password": ""
  }
} 
`