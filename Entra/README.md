# CSV Output Headers Reference

This document provides a quick reference for all CSV file headers produced by the Entra data collection scripts.

---

## User Data Collectors

### EntraUsers-BasicData_timestamp.csv

"UserPrincipalName","Id","accountEnabled","UserType","CustomSecurityAttributes","createdDateTime","LastSignInDateTime","OnPremisesSyncEnabled","OnPremisesSamAccountName","PasswordPolicies"

**10 columns** | One row per user | Core user information without licenses

**Example**

"UserPrincipalName","Id","accountEnabled","UserType","CustomSecurityAttributes","createdDateTime","LastSignInDateTime","OnPremisesSyncEnabled","OnPremisesSamAccountName","PasswordPolicies"
"john.doe@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","1","Member","","2023-01-15 08:30:00","2024-12-10 14:22:00","0","","DisablePasswordExpiration"
"jane.smith@contoso.com","b2c3d4e5-f6g7-8901-bcde-fg2345678901","1","Member","","2022-06-20 10:15:00","2024-12-11 09:45:00","1","jsmith",""
"admin.user@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","1","Member","","2021-03-10 12:00:00","2024-12-11 11:30:00","0","","DisableStrongPassword"
"guest.external@external.com","d4e5f6g7-h8i9-0123-defg-hi4567890123","1","Guest","","2024-05-05 16:20:00","2024-11-28 13:10:00","0","",""
"service.account@contoso.com","e5f6g7h8-i9j0-1234-efgh-ij5678901234","0","Member","","2023-09-12 07:45:00","","0","","DisablePasswordExpiration"
"maria.garcia@contoso.com","f6g7h8i9-j0k1-2345-fghi-jk6789012345","1","Member","","2023-07-22 14:15:00","2024-12-09 16:45:00","0","","DisablePasswordExpiration"
"bob.wilson@contoso.com","g7h8i9j0-k1l2-3456-ghij-kl7890123456","1","Member","","2022-11-03 09:30:00","2024-12-08 11:20:00","1","bwilson",""
"contractor.temp@external.com","h8i9j0k1-l2m3-4567-hijk-lm8901234567","1","Guest","","2024-09-01 08:00:00","2024-12-11 10:15:00","0","",""
"disabled.user@contoso.com","i9j0k1l2-m3n4-5678-ijkl-mn9012345678","0","Member","","2020-01-15 12:00:00","2024-08-30 14:22:00","0","","DisablePasswordExpiration"
"new.hire@contoso.com","j0k1l2m3-n4o5-6789-jklm-no0123456789","1","Member","","2024-12-01 09:00:00","2024-12-11 09:30:00","0","",""


---

### EntraUsers-Licenses_timestamp.csv

"UserPrincipalName","UserId","License"

**3 columns** | One row per license | User license assignments

**Example**

"UserPrincipalName","UserId","License"
"john.doe@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","ENTERPRISEPACK"
"john.doe@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","POWER_BI_PRO"
"jane.smith@contoso.com","b2c3d4e5-f6g7-8901-bcde-fg2345678901","ENTERPRISEPACK"
"admin.user@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","ENTERPRISEPREMIUM"
"admin.user@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","EMS"
"maria.garcia@contoso.com","f6g7h8i9-j0k1-2345-fghi-jk6789012345","ENTERPRISEPACK"
"maria.garcia@contoso.com","f6g7h8i9-j0k1-2345-fghi-jk6789012345","TEAMS_EXPLORATORY"
"bob.wilson@contoso.com","g7h8i9j0-k1l2-3456-ghij-kl7890123456","POWER_BI_STANDARD"
"disabled.user@contoso.com","i9j0k1l2-m3n4-5678-ijkl-mn9012345678","ENTERPRISEPACK"
"admin.user@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","VISIOCLIENT"


---

### EntraUsers-Groups_timestamp.csv

"UserPrincipalName","GroupId","GroupName","GroupRoleAssignable","GroupType","GroupMembershipType","GroupSecurityEnabled","MembershipPath"

**8 columns** | One row per group membership | User group memberships (direct and inherited)

**Example**

"UserPrincipalName","GroupId","GroupName","GroupRoleAssignable","GroupType","GroupMembershipType","GroupSecurityEnabled","MembershipPath"
"john.doe@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","All Employees","0","Security","Assigned","1","Direct"
"john.doe@contoso.com","b2c3d4e5-f6g7-8901-bcde-fg2345678901","Sales Team","0","Security","Dynamic","1","Direct"
"john.doe@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","Office 365 Users","0","Microsoft 365","Assigned","0","Inherited"
"john.doe@contoso.com","d4e5f6g7-h8i9-0123-defg-hi4567890123","Sales-Regional-West","0","Security","Assigned","1","Inherited"
"jane.smith@contoso.com","e5f6g7h8-i9j0-1234-efgh-ij5678901234","IT Department","1","Security","Assigned","1","Direct"
"jane.smith@contoso.com","f6g7h8i9-j0k1-2345-fghi-jk6789012345","Security Admins","1","Security","Assigned","1","Inherited"
"jane.smith@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","All Employees","0","Security","Assigned","1","Direct"
"admin.user@contoso.com","g7h8i9j0-k1l2-3456-ghij-kl7890123456","Global IT","0","Security","Assigned","1","Direct"
"admin.user@contoso.com","h8i9j0k1-l2m3-4567-hijk-lm8901234567","Helpdesk Tier 2","0","Security","Assigned","1","Direct"
"admin.user@contoso.com","i9j0k1l2-m3n4-5678-ijkl-mn9012345678","Azure Administrators","1","Security","Assigned","1","Inherited"


---

### EntraUsers-AllPermissions_timestamp.csv

"UserPrincipalName","Id","EntraRole","EntraRoleType","GraphPermissionType","GraphPermission","AppId","AppName","ResourceId","ResourceName"

**10 columns** | One row per permission | Combined Entra roles and Graph API permissions

**Example**

"UserPrincipalName","Id","EntraRole","EntraRoleType","GraphPermissionType","GraphPermission","AppId","AppName","ResourceId","ResourceName"
"john.doe@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","","","Delegated","User.Read","a1b2c3d4-client-app","","00000003-0000-0000-c000-000000000000","Microsoft Graph"
"john.doe@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","","","Delegated","Mail.Send","a1b2c3d4-client-app","","00000003-0000-0000-c000-000000000000","Microsoft Graph"
"john.doe@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","","","Delegated","Calendars.ReadWrite","b2c3d4e5-other-app","","00000003-0000-0000-c000-000000000000","Microsoft Graph"
"jane.smith@contoso.com","b2c3d4e5-f6g7-8901-bcde-fg2345678901","Global Administrator","PIM","","","","","",""
"jane.smith@contoso.com","b2c3d4e5-f6g7-8901-bcde-fg2345678901","Security Administrator","Permanent","","","","","",""
"jane.smith@contoso.com","b2c3d4e5-f6g7-8901-bcde-fg2345678901","","","Application","Directory.Read.All","c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","d5e6f7g8-resource-id","Custom HR App"
"jane.smith@contoso.com","b2c3d4e5-f6g7-8901-bcde-fg2345678901","","","Delegated","User.ReadWrite.All","e5f6g7h8-admin-app","","00000003-0000-0000-c000-000000000000","Microsoft Graph"
"admin.user@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","User Administrator","Group-Permanent (IT Admins)","","","","","",""
"admin.user@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","Helpdesk Administrator","Permanent","","","","","",""
"admin.user@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","","","Delegated","User.Read.All","f6g7h8i9-helpdesk","","00000003-0000-0000-c000-000000000000","Microsoft Graph"


---

## Group Data Collectors

### EntraGroups-BasicData_timestamp.csv

"GroupId","GroupName","classification","deletedDateTime","description","mailEnabled","membershipRule","securityEnabled","isAssignableToRole"

**9 columns** | One row per group | Core group information without types/tags

**Example**

"GroupId","GroupName","classification","deletedDateTime","description","mailEnabled","membershipRule","securityEnabled","isAssignableToRole"
"a1b2c3d4-e5f6-7890-abcd-ef1234567890","All Employees","General","","Company-wide security group","0","","1","0"
"b2c3d4e5-f6g7-8901-bcde-fg2345678901","Sales Team","","","Dynamic group for sales department","0","user.department -eq 'Sales'","1","0"
"c3d4e5f6-g7h8-9012-cdef-gh3456789012","IT Admins","Restricted","","Role-assignable admin group","0","","1","1"
"d4e5f6g7-h8i9-0123-defg-hi4567890123","Marketing","","","Marketing department group","1","","0","0"
"e5f6g7h8-i9j0-1234-efgh-ij5678901234","Archived-OldProject","","2024-10-15 09:30:00","Deleted project team","1","","0","0"
"f6g7h8i9-j0k1-2345-fghi-jk6789012345","Finance Team","Confidential","","Finance and accounting staff","0","","1","1"
"g7h8i9j0-k1l2-3456-ghij-kl7890123456","Remote Workers","","","Employees working remotely","0","user.extensionAttribute1 -eq 'Remote'","1","0"
"h8i9j0k1-l2m3-4567-hijk-lm8901234567","Office 365 Users","","","All O365 licensed users","1","","0","0"
"i9j0k1l2-m3n4-5678-ijkl-mn9012345678","Contractors","","","External contractor access","0","","1","0"
"j0k1l2m3-n4o5-6789-jklm-no0123456789","Engineering-DevOps","","","DevOps engineering team","1","","1","0"


---

### EntraGroups-Types_timestamp.csv

"GroupId","GroupName","GroupType"

**3 columns** | One row per group type | Group type assignments (Unified, DynamicMembership, etc.)

**Example**

"GroupId","GroupName","GroupType"
"b2c3d4e5-f6g7-8901-bcde-fg2345678901","Sales Team","Unified"
"d4e5f6g7-h8i9-0123-defg-hi4567890123","Marketing","Unified"
"h8i9j0k1-l2m3-4567-hijk-lm8901234567","Office 365 Users","Unified"
"j0k1l2m3-n4o5-6789-jklm-no0123456789","Engineering-DevOps","Unified"
"k1l2m3n4-o5p6-7890-klmn-op1234567890","Project Alpha","DynamicMembership"
"l2m3n4o5-p6q7-8901-lmno-pq2345678901","Research Team","Unified"
"m3n4o5p6-q7r8-9012-mnop-qr3456789012","Development","Unified"
"n4o5p6q7-r8s9-0123-nopq-rs4567890123","Quality Assurance","DynamicMembership"
"o5p6q7r8-s9t0-1234-opqr-st5678901234","Product Management","Unified"
"p6q7r8s9-t0u1-2345-pqrs-tu6789012345","Customer Success","Unified"


---

### EntraGroups-Tags_timestamp.csv

"GroupId","GroupName","Tag"

**3 columns** | One row per tag | Group tag assignments

**Example**

"GroupId","GroupName","Tag"
"a1b2c3d4-e5f6-7890-abcd-ef1234567890","All Employees","CompanyWide"
"c3d4e5f6-g7h8-9012-cdef-gh3456789012","IT Admins","Administrative"
"c3d4e5f6-g7h8-9012-cdef-gh3456789012","IT Admins","RoleAssignable"
"f6g7h8i9-j0k1-2345-fghi-jk6789012345","Finance Team","Confidential"
"f6g7h8i9-j0k1-2345-fghi-jk6789012345","Finance Team","RoleAssignable"
"j0k1l2m3-n4o5-6789-jklm-no0123456789","Engineering-DevOps","Technical"
"k1l2m3n4-o5p6-7890-klmn-op1234567890","Project Alpha","ProjectBased"
"k1l2m3n4-o5p6-7890-klmn-op1234567890","Project Alpha","Temporary"
"l2m3n4o5-p6q7-8901-lmno-pq2345678901","Research Team","Innovation"
"m3n4o5p6-q7r8-9012-mnop-qr3456789012","Development","Engineering"


---

### EntraGroups-Relationships_timestamp.csv

"GroupId","GroupName","GroupType","RelatedGroupId","RelatedGroupName","RelationshipType"

**6 columns** | One row per relationship | Group nesting relationships (Contains or MemberOf)

**Example**

"GroupId","GroupName","GroupType","RelatedGroupId","RelatedGroupName","RelationshipType"
"b2c3d4e5-f6g7-8901-bcde-fg2345678901","Sales Team","Security","x1y2z3a4-nested1","Regional Sales","Contains"
"b2c3d4e5-f6g7-8901-bcde-fg2345678901","Sales Team","Security","x2y3z4a5-nested2","Enterprise Sales","Contains"
"c3d4e5f6-g7h8-9012-cdef-gh3456789012","IT Admins","Security","h1i2j3k4-helpdesk","Helpdesk Team","Contains"
"c3d4e5f6-g7h8-9012-cdef-gh3456789012","IT Admins","Security","s1e2r3v4-server","Server Admins","Contains"
"x1y2z3a4-nested1","Regional Sales","Security","b2c3d4e5-f6g7-8901-bcde-fg2345678901","Sales Team","MemberOf"
"x1y2z3a4-nested1","Regional Sales","Security","r1e2v3e4-revenue","Revenue Teams","MemberOf"
"h1i2j3k4-helpdesk","Helpdesk Team","Security","t1i2e3r4-tier1","Tier 1 Support","Contains"
"h1i2j3k4-helpdesk","Helpdesk Team","Security","t2i2e3r4-tier2","Tier 2 Support","Contains"
"h1i2j3k4-helpdesk","Helpdesk Team","Security","c3d4e5f6-g7h8-9012-cdef-gh3456789012","IT Admins","MemberOf"
"e1x2e3c4-exec","Executive Leadership","Security","c1s2u3i4-csuite","C-Suite","Contains"


---

## Service Principal Data Collectors

### EntraServicePrincipals-BasicData_timestamp.csv

"ServicePrincipalId","ServicePrincipalName","accountEnabled","appDescription","appId","appRoleAssignmentRequired","deletedDateTime","description","preferredSingleSignOnMode","servicePrincipalType"

**10 columns** | One row per service principal | Core service principal information

**Example**

"ServicePrincipalId","ServicePrincipalName","accountEnabled","appDescription","appId","appRoleAssignmentRequired","deletedDateTime","description","preferredSingleSignOnMode","servicePrincipalType"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","1","The Microsoft Graph API","00000003-0000-0000-c000-000000000000","0","","Provides access to Microsoft 365 data","","Application"
"sp-c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","1","Internal HR application","c4d5e6f7-g8h9-0123-4567-890abcdef123","1","","Employee data management system","","Application"
"sp-d5e6f7g8-h9i0-1234-5678-901abcdef234","Legacy ERP System","0","Deprecated ERP","d5e6f7g8-h9i0-1234-5678-901abcdef234","0","2024-11-01 10:00:00","Old financial system - disabled","","Application"
"sp-e6f7g8h9-i0j1-2345-6789-012bcdef3456","Power BI Service","1","Business intelligence","e6f7g8h9-i0j1-2345-6789-012bcdef3456","0","","Analytics and reporting platform","","Application"
"sp-f7g8h9i0-j1k2-3456-7890-123cdef45678","SharePoint Online","1","Document management","f7g8h9i0-j1k2-3456-7890-123cdef45678","0","","Collaboration and file storage","","Application"
"sp-g8h9i0j1-k2l3-4567-8901-234def567890","Azure DevOps","1","CI/CD platform","g8h9i0j1-k2l3-4567-8901-234def567890","0","","Development and deployment pipelines","","Application"
"sp-h9i0j1k2-l3m4-5678-9012-345ef6789012","Salesforce Connector","1","CRM integration","h9i0j1k2-l3m4-5678-9012-345ef6789012","1","","Sales data synchronization","","Application"
"sp-i0j1k2l3-m4n5-6789-0123-456fg7890123","Mobile App - iOS","1","Company mobile app","i0j1k2l3-m4n5-6789-0123-456fg7890123","1","","Employee mobile application","","Application"
"sp-j1k2l3m4-n5o6-7890-1234-567gh8901234","Backup Service","1","Data backup","j1k2l3m4-n5o6-7890-1234-567gh8901234","0","","Automated backup system","","Application"
"sp-k2l3m4n5-o6p7-8901-2345-678hi9012345","Monitoring Dashboard","1","System monitoring","k2l3m4n5-o6p7-8901-2345-678hi9012345","0","","Real-time system health monitoring","","Application"


---

### EntraServicePrincipals-OAuth2Permissions_timestamp.csv

"ServicePrincipalId","ServicePrincipalName","OAuth2PermissionScope"

**3 columns** | One row per OAuth2 scope | OAuth2 permission scopes (delegated permissions)

**Example**

"ServicePrincipalId","ServicePrincipalName","OAuth2PermissionScope"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","User.Read"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","Mail.Send"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","Calendars.Read"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","Files.ReadWrite"
"sp-c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","Employee.Read"
"sp-c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","Department.ReadWrite"
"sp-e6f7g8h9-i0j1-2345-6789-012bcdef3456","Power BI Service","Dashboard.Read"
"sp-e6f7g8h9-i0j1-2345-6789-012bcdef3456","Power BI Service","Report.Read"
"sp-f7g8h9i0-j1k2-3456-7890-123cdef45678","SharePoint Online","Sites.Read.All"
"sp-f7g8h9i0-j1k2-3456-7890-123cdef45678","SharePoint Online","Files.ReadWrite.All"


---

### EntraServicePrincipals-AppPermissions_timestamp.csv

"ServicePrincipalId","ServicePrincipalName","ResourceSpecificApplicationPermission"

**3 columns** | One row per app permission | Resource-specific application permissions

**Example**

"ServicePrincipalId","ServicePrincipalName","ResourceSpecificApplicationPermission"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","TeamSettings.Read.All"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","Channel.ReadBasic.All"
"sp-c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","EmployeeData.ReadWrite.All"
"sp-e6f7g8h9-i0j1-2345-6789-012bcdef3456","Power BI Service","Dataset.Read.All"
"sp-f7g8h9i0-j1k2-3456-7890-123cdef45678","SharePoint Online","Sites.FullControl.All"
"sp-g8h9i0j1-k2l3-4567-8901-234def567890","Azure DevOps","Build.Execute"
"sp-h9i0j1k2-l3m4-5678-9012-345ef6789012","Salesforce Connector","Account.ReadWrite.All"
"sp-i0j1k2l3-m4n5-6789-0123-456fg7890123","Mobile App - iOS","Presence.Read.All"
"sp-j1k2l3m4-n5o6-7890-1234-567gh8901234","Backup Service","Files.Read.All"
"sp-k2l3m4n5-o6p7-8901-2345-678hi9012345","Monitoring Dashboard","AuditLog.Read.All"


---

### EntraServicePrincipals-Names_timestamp.csv

"ServicePrincipalId","ServicePrincipalName","ServicePrincipalNameValue"

**3 columns** | One row per service principal name | Service principal name URIs and identifiers

**Example**

"ServicePrincipalId","ServicePrincipalName","ServicePrincipalNameValue"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","https://graph.microsoft.com"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","00000003-0000-0000-c000-000000000000"
"sp-c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","api://hr-app-prod"
"sp-c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","https://hr.contoso.com"
"sp-e6f7g8h9-i0j1-2345-6789-012bcdef3456","Power BI Service","https://analysis.windows.net/powerbi/api"
"sp-f7g8h9i0-j1k2-3456-7890-123cdef45678","SharePoint Online","https://sharepoint.com"
"sp-f7g8h9i0-j1k2-3456-7890-123cdef45678","SharePoint Online","https://contoso.sharepoint.com"
"sp-g8h9i0j1-k2l3-4567-8901-234def567890","Azure DevOps","https://dev.azure.com"
"sp-h9i0j1k2-l3m4-5678-9012-345ef6789012","Salesforce Connector","api://salesforce-connector"
"sp-i0j1k2l3-m4n5-6789-0123-456fg7890123","Mobile App - iOS","api://mobile-app-ios"


---

### EntraServicePrincipals-Tags_timestamp.csv

"ServicePrincipalId","ServicePrincipalName","Tag"

**3 columns** | One row per tag | Service principal tags

**Example**

"ServicePrincipalId","ServicePrincipalName","Tag"
"sp-00000003-0000-0000-c000-000000000000","Microsoft Graph","WindowsAzureActiveDirectoryIntegratedApp"
"sp-c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","HideApp"
"sp-c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","WindowsAzureActiveDirectoryIntegratedApp"
"sp-e6f7g8h9-i0j1-2345-6789-012bcdef3456","Power BI Service","WindowsAzureActiveDirectoryIntegratedApp"
"sp-g8h9i0j1-k2l3-4567-8901-234def567890","Azure DevOps","WindowsAzureActiveDirectoryIntegratedApp"
"sp-h9i0j1k2-l3m4-5678-9012-345ef6789012","Salesforce Connector","HideApp"
"sp-i0j1k2l3-m4n5-6789-0123-456fg7890123","Mobile App - iOS","WindowsAzureActiveDirectoryIntegratedApp"
"sp-j1k2l3m4-n5o6-7890-1234-567gh8901234","Backup Service","WindowsAzureActiveDirectoryIntegratedApp"
"sp-k2l3m4n5-o6p7-8901-2345-678hi9012345","Monitoring Dashboard","WindowsAzureActiveDirectoryIntegratedApp"
"sp-f7g8h9i0-j1k2-3456-7890-123cdef45678","SharePoint Online","WindowsAzureActiveDirectoryIntegratedApp"


---

## Naming Convention Standards

### User-related CSVs
All user-related CSVs start with:

"UserPrincipalName","Id",...


### Group-related CSVs
All group-related CSVs start with:

"GroupId","GroupName",...


### Service Principal-related CSVs
All service principal-related CSVs start with:

"ServicePrincipalId","ServicePrincipalName",...


---

## Total Output Files

| Script | CSV Files Produced | Total |
|--------|-------------------|-------|
| EntraUsersAndGroups.ps1 | BasicData, Licenses, Groups | 3 |
| EntraGroups.ps1 | BasicData, Types, Tags | 3 |
| EntraGroupsNested.ps1 | Relationships | 1 |
| EntraPermissions.ps1 | AllPermissions | 1 |
| EntraServicePrincipals.ps1 | BasicData, OAuth2Permissions, AppPermissions, Names, Tags | 5 |
| **Total** | | **13 CSV files** |

---

## Key Field Meanings

### Common Fields

| Field | Description |
|-------|-------------|
| `Id` / `UserId` | User's unique GUID identifier |
| `GroupId` | Group's unique GUID identifier |
| `ServicePrincipalId` | Service Principal's unique GUID identifier |
| `UserPrincipalName` | User's email/login (e.g., john.doe@contoso.com) |
| `GroupName` | Group's display name |
| `ServicePrincipalName` | Service Principal's display name |

### Boolean Fields (represented as "1" or "0")

| Field | Description |
|-------|-------------|
| `accountEnabled` | Account is active (1) or disabled (0) |
| `mailEnabled` | Group has email enabled |
| `securityEnabled` | Group is security-enabled |
| `isAssignableToRole` | Group can be assigned to Entra roles |
| `OnPremisesSyncEnabled` | Synced from on-premises AD |
| `GroupRoleAssignable` | Group can be assigned to roles |
| `appRoleAssignmentRequired` | Requires role assignment for access |

### Relationship Types

| Value | Description |
|-------|-------------|
| `Contains` | Parent group contains the related group |
| `MemberOf` | Group is a member of the related group |
| `Direct` | User is directly assigned to the group |
| `Inherited` | User has membership through nested groups |

### Group Types

| Value | Description |
|-------|-------------|
| `Security` | Security group |
| `Microsoft 365` | Microsoft 365 group (formerly Office 365) |
| `Distribution` | Distribution list |
| `Mail-enabled Security` | Security group with email |
| `Unified` | Modern group type (often Microsoft 365) |
| `DynamicMembership` | Group with dynamic membership rules |

### Permission Types

| Value | Description |
|-------|-------------|
| `Delegated` | Permissions granted on behalf of a user |
| `Application` | Permissions granted directly to an application |

### Role Assignment Types

| Value | Description |
|-------|-------------|
| `Permanent` | Permanently assigned role |
| `PIM` | Eligible for Privileged Identity Management activation |
| `Group-Permanent (GroupName)` | Inherited from permanent group assignment |
| `Group-PIM (GroupName)` | Inherited from PIM-eligible group |

---

## Empty Values

All empty/null values are represented as empty strings `""` (no "NULL" text).

Example:

"john.doe@contoso.com","abc-123","1","Member","","2023-01-15 08:30:00","","0","",""


---

## Joining CSVs

### Join Users with Licenses

EntraUsers-BasicData.Id = EntraUsers-Licenses.UserId


### Join Users with Groups

EntraUsers-BasicData.UserPrincipalName = EntraUsers-Groups.UserPrincipalName


### Join Users with Permissions

EntraUsers-BasicData.UserPrincipalName = EntraUsers-AllPermissions.UserPrincipalName


### Join Groups with Types

EntraGroups-BasicData.GroupId = EntraGroups-Types.GroupId


### Join Groups with Tags

EntraGroups-BasicData.GroupId = EntraGroups-Tags.GroupId


### Join Groups with Relationships

EntraGroups-BasicData.GroupId = EntraGroups-Relationships.GroupId


### Join Service Principals with OAuth2 Permissions

EntraServicePrincipals-BasicData.ServicePrincipalId = EntraServicePrincipals-OAuth2Permissions.ServicePrincipalId


### Join Service Principals with App Permissions

EntraServicePrincipals-BasicData.ServicePrincipalId = EntraServicePrincipals-AppPermissions.ServicePrincipalId


### Join Service Principals with Names

EntraServicePrincipals-BasicData.ServicePrincipalId = EntraServicePrincipals-Names.ServicePrincipalId


### Join Service Principals with Tags

EntraServicePrincipals-BasicData.ServicePrincipalId = EntraServicePrincipals-Tags.ServicePrincipalId
