# Entra Data Collection Scripts

blah

## Field Mappings

### EntraUsers-Groups.csv
- `GroupId` → Use for filtering/matching with EntraGroups.csv
- `GroupName` → Human-readable name for quick reference

### EntraGroups-Nested.csv
- `GroupId` → The group being analyzed
- `GroupName` → Name of the group being analyzed
- `NestedGroupIds` → Pipe-delimited list of child group IDs
- `NestedGroupNames` → Pipe-delimited list of child group names (same order as IDs)
- `ParentGroupIds` → Pipe-delimited list of parent group IDs
- `ParentGroupNames` → Pipe-delimited list of parent group names (same order as IDs)

### EntraUsers-AllPermissions.csv
- `AppId` → Application ID (use for matching with EntraServicePrincipals.csv)
- `AppName` → Application name (human-readable, may be NULL for some delegated permissions)
- `ResourceId` → Resource ID being accessed (e.g., Microsoft Graph ID)
- `ResourceName` → Resource name (e.g., "Microsoft Graph")

## CSV Output Examples

### 1. EntraUsers-BasicData_timestamp.csv

"UserPrincipalName","Id","accountEnabled","UserType","assignedLicenses","CustomSecurityAttributes","createdDateTime","LastSignInDateTime","OnPremisesSyncEnabled","OnPremisesSamAccountName","PasswordPolicies"
"john.doe@contoso.com","a1b2c3d4-e5f6-7890-abcd-ef1234567890","1","Member","ENTERPRISEPACK | POWER_BI_PRO","NULL","2023-01-15 08:30:00","2024-12-10 14:22:00","0","NULL","DisablePasswordExpiration"
"jane.smith@contoso.com","b2c3d4e5-f6g7-8901-bcde-fg2345678901","1","Member","ENTERPRISEPACK","NULL","2022-06-20 10:15:00","2024-12-11 09:45:00","1","jsmith","NULL"
"admin.user@contoso.com","c3d4e5f6-g7h8-9012-cdef-gh3456789012","1","Member","ENTERPRISEPREMIUM | EMS","NULL","2021-03-10 12:00:00","2024-12-11 11:30:00","0","NULL","DisableStrongPassword | DisablePasswordExpiration"
"guest.external@external.com","d4e5f6g7-h8i9-0123-defg-hi4567890123","1","Guest","NULL","NULL","2024-05-05 16:20:00","2024-11-28 13:10:00","0","NULL","NULL"
"service.account@contoso.com","e5f6g7h8-i9j0-1234-efgh-ij5678901234","0","Member","NULL","NULL","2023-09-12 07:45:00","NULL","0","NULL","DisablePasswordExpiration"
"maria.garcia@contoso.com","f6g7h8i9-j0k1-2345-fghi-jk6789012345","1","Member","ENTERPRISEPACK | TEAMS_EXPLORATORY","NULL","2023-07-22 14:15:00","2024-12-09 16:45:00","0","NULL","DisablePasswordExpiration"
"bob.wilson@contoso.com","g7h8i9j0-k1l2-3456-ghij-kl7890123456","1","Member","POWER_BI_STANDARD","NULL","2022-11-03 09:30:00","2024-12-08 11:20:00","1","bwilson","NULL"
"contractor.temp@external.com","h8i9j0k1-l2m3-4567-hijk-lm8901234567","1","Guest","NULL","NULL","2024-09-01 08:00:00","2024-12-11 10:15:00","0","NULL","NULL"
"disabled.user@contoso.com","i9j0k1l2-m3n4-5678-ijkl-mn9012345678","0","Member","ENTERPRISEPACK","NULL","2020-01-15 12:00:00","2024-08-30 14:22:00","0","NULL","DisablePasswordExpiration"
"new.hire@contoso.com","j0k1l2m3-n4o5-6789-jklm-no0123456789","1","Member","NULL","NULL","2024-12-01 09:00:00","2024-12-11 09:30:00","0","NULL","NULL"


### 2. EntraUsers-Groups_timestamp.csv

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


### 3. EntraUsers-AllPermissions_timestamp.csv

"UserPrincipalName","EntraRole","EntraRoleType","GraphPermissionType","GraphPermission","AppId","AppName","ResourceId","ResourceName"
"john.doe@contoso.com","NULL","NULL","Delegated","User.Read","a1b2c3d4-client-app","NULL","00000003-0000-0000-c000-000000000000","Microsoft Graph"
"john.doe@contoso.com","NULL","NULL","Delegated","Mail.Send","a1b2c3d4-client-app","NULL","00000003-0000-0000-c000-000000000000","Microsoft Graph"
"john.doe@contoso.com","NULL","NULL","Delegated","Calendars.ReadWrite","b2c3d4e5-other-app","NULL","00000003-0000-0000-c000-000000000000","Microsoft Graph"
"jane.smith@contoso.com","Global Administrator","PIM","NULL","NULL","NULL","NULL","NULL","NULL"
"jane.smith@contoso.com","Security Administrator","Permanent","NULL","NULL","NULL","NULL","NULL","NULL"
"jane.smith@contoso.com","NULL","NULL","Application","Directory.Read.All","c4d5e6f7-g8h9-0123-4567-890abcdef123","Custom HR App","d5e6f7g8-resource-id","Custom HR App"
"jane.smith@contoso.com","NULL","NULL","Delegated","User.ReadWrite.All","e5f6g7h8-admin-app","NULL","00000003-0000-0000-c000-000000000000","Microsoft Graph"
"admin.user@contoso.com","User Administrator","Group-Permanent (IT Admins)","NULL","NULL","NULL","NULL","NULL","NULL"
"admin.user@contoso.com","Helpdesk Administrator","Permanent","NULL","NULL","NULL","NULL","NULL","NULL"
"admin.user@contoso.com","NULL","NULL","Delegated","User.Read.All","f6g7h8i9-helpdesk","NULL","00000003-0000-0000-c000-000000000000","Microsoft Graph"


### 4. EntraGroups_timestamp.csv

"displayName","Id","classification","deletedDateTime","description","groupTypes","mailEnabled","membershipRule","securityEnabled","isAssignableToRole"
"All Employees","a1b2c3d4-e5f6-7890-abcd-ef1234567890","General","NULL","Company-wide security group","NULL","0","NULL","1","0"
"Sales Team","b2c3d4e5-f6g7-8901-bcde-fg2345678901","NULL","NULL","Dynamic group for sales department","Unified","0","user.department -eq 'Sales'","1","0"
"IT Admins","c3d4e5f6-g7h8-9012-cdef-gh3456789012","Restricted","NULL","Role-assignable admin group","NULL","0","NULL","1","1"
"Marketing","d4e5f6g7-h8i9-0123-defg-hi4567890123","NULL","NULL","Marketing department group","Unified","1","NULL","0","0"
"Archived-OldProject","e5f6g7h8-i9j0-1234-efgh-ij5678901234","NULL","2024-10-15 09:30:00","Deleted project team","Unified","1","NULL","0","0"
"Finance Team","f6g7h8i9-j0k1-2345-fghi-jk6789012345","Confidential","NULL","Finance and accounting staff","NULL","0","NULL","1","1"
"Remote Workers","g7h8i9j0-k1l2-3456-ghij-kl7890123456","NULL","NULL","Employees working remotely","NULL","0","user.extensionAttribute1 -eq 'Remote'","1","0"
"Office 365 Users","h8i9j0k1-l2m3-4567-hijk-lm8901234567","NULL","NULL","All O365 licensed users","Unified","1","NULL","0","0"
"Contractors","i9j0k1l2-m3n4-5678-ijkl-mn9012345678","NULL","NULL","External contractor access","NULL","0","NULL","1","0"
"Engineering-DevOps","j0k1l2m3-n4o5-6789-jklm-no0123456789","NULL","NULL","DevOps engineering team","Unified","1","NULL","1","0"


### 5. EntraGroups-Nested_timestamp.csv

"GroupId","GroupName","GroupType","NestedGroupIds","NestedGroupNames","NestedGroupCount","ParentGroupIds","ParentGroupNames","ParentGroupCount","TotalRelationships"
"a1b2c3d4-e5f6-7890-abcd-ef1234567890","All Employees","Security","NULL","NULL","0","NULL","NULL","0","0"
"b2c3d4e5-f6g7-8901-bcde-fg2345678901","Sales Team","Security","x1y2z3a4-nested1 | x2y3z4a5-nested2","Regional Sales | Enterprise Sales","2","p1q2r3s4-parent1 | p2q3r4s5-parent2","All Employees | Revenue Teams","2","4"
"c3d4e5f6-g7h8-9012-cdef-gh3456789012","IT Admins","Security","h1i2j3k4-helpdesk | s1e2r3v4-server | n1e2t3w4-network","Helpdesk Team | Server Admins | Network Team","3","g1l2o3b4-global","Global Admins","1","4"
"d4e5f6g7-h8i9-0123-defg-hi4567890123","Marketing","Microsoft 365","NULL","NULL","0","a1b2c3d4-e5f6-7890-abcd-ef1234567890","All Employees","1","1"
"f6g7h8i9-j0k1-2345-fghi-jk6789012345","Finance Team","Security","a1c2c3t4-acct | p1a2y3r4-payroll | b1u2d3g4-budget","Accounting | Payroll | Budget Planning","3","e1x2e3c4-exec | a1b2c3d4-allemp","Executive Leadership | All Employees","2","5"
"x1y2z3a4-nested1","Regional Sales","Security","NULL","NULL","0","b2c3d4e5-f6g7-8901-bcde-fg2345678901 | r1e2v3e4-revenue","Sales Team | Revenue Teams","2","2"
"h1i2j3k4-helpdesk","Helpdesk Team","Security","t1i2e3r4-tier1 | t2i2e3r4-tier2","Tier 1 Support | Tier 2 Support","2","c3d4e5f6-g7h8-9012-cdef-gh3456789012 | s1u2p3p4-support","IT Admins | Support Organization","2","4"
"e1x2e3c4-exec","Executive Leadership","Security","c1s2u3i4-csuite | v1p2s3-vps","C-Suite | VPs","2","b1o2a3r4-board","Board Members","1","3"
"j0k1l2m3-n4o5-6789-jklm-no0123456789","Engineering-DevOps","Microsoft 365","p1l2a3t4-platform | r1e2l3e4-release","Platform Team | Release Team","2","e1n2g3i4-eng | c3d4e5f6-itdept","Engineering | IT Department","2","4"
"k1l2m3n4-o5p6-7890-klmn-op1234567890","Security Operations","Security","s1o2c3-analysts | i1n2c3-incident","SOC Analysts | Incident Response","2","f6g7h8i9-secadmin | c3d4e5f6-itadmin","Security Admins | IT Admins","2","4"


### 6. EntraServicePrincipals_timestamp.csv

"displayName","accountEnabled","addIns","appDescription","appId","appRoleAssignmentRequired","deletedDateTime","description","oauth2PermissionScopes","preferredSingleSignOnMode","resourceSpecificApplicationPermissions","servicePrincipalNames","servicePrincipalType","tags"
"Microsoft Graph","1","NULL","The Microsoft Graph API","00000003-0000-0000-c000-000000000000","0","NULL","Provides access to Microsoft 365 data","User.Read | Mail.Send | Calendars.Read | Files.ReadWrite","NULL","NULL","https://graph.microsoft.com","Application","WindowsAzureActiveDirectoryIntegratedApp"
"Custom HR App","1","NULL","Internal HR application","c4d5e6f7-g8h9-0123-4567-890abcdef123","1","NULL","Employee data management system","Employee.Read | Department.ReadWrite","NULL","NULL","api://hr-app-prod | https://hr.contoso.com","Application","HideApp | WindowsAzureActiveDirectoryIntegratedApp"
"Legacy ERP System","0","NULL","Deprecated ERP","d5e6f7g8-h9i0-1234-5678-901abcdef234","0","2024-11-01 10:00:00","Old financial system - disabled","NULL","NULL","NULL","https://erp.company.local","Application","NULL"
"Power BI Service","1","NULL","Business intelligence","e6f7g8h9-i0j1-2345-6789-012bcdef3456","0","NULL","Analytics and reporting platform","Dashboard.Read | Report.Read | Dataset.ReadWrite.All","NULL","NULL","https://analysis.windows.net/powerbi/api","Application","WindowsAzureActiveDirectoryIntegratedApp"
"SharePoint Online","1","NULL","Document management","f7g8h9i0-j1k2-3456-7890-123cdef45678","0","NULL","Collaboration and file storage","Sites.Read.All | Files.ReadWrite.All | Lists.ReadWrite","NULL","NULL","https://sharepoint.com | https://tenant.sharepoint.com","Application","WindowsAzureActiveDirectoryIntegratedApp"
"Azure DevOps","1","NULL","CI/CD platform","g8h9i0j1-k2l3-4567-8901-234def567890","0","NULL","Development and deployment pipelines","Build.Read | Release.Manage | Code.ReadWrite","NULL","NULL","https://dev.azure.com","Application","WindowsAzureActiveDirectoryIntegratedApp"
"Salesforce Connector","1","NULL","CRM integration","h9i0j1k2-l3m4-5678-9012-345ef6789012","1","NULL","Sales data synchronization","Account.ReadWrite | Opportunity.Read | Lead.ReadWrite","NULL","NULL","api://salesforce-connector","Application","HideApp"
"Mobile App - iOS","1","NULL","Company mobile app","i0j1k2l3-m4n5-6789-0123-456fg7890123","1","NULL","Employee mobile application","User.Read | Presence.Read | Mail.Send","NULL","NULL","api://mobile-app-ios","Application","WindowsAzureActiveDirectoryIntegratedApp"
"Backup Service","1","NULL","Data backup","j1k2l3m4-n5o6-7890-1234-567gh8901234","0","NULL","Automated backup system","Files.Read.All | Sites.Read.All | Mail.Read","NULL","NULL","https://backup.contoso.com","Application","WindowsAzureActiveDirectoryIntegratedApp"
"Monitoring Dashboard","1","NULL","System monitoring","k2l3m4n5-o6p7-8901-2345-678hi9012345","0","NULL","Real-time system health monitoring","AuditLog.Read.All | Directory.Read.All | Reports.Read.All","NULL","NULL","https://monitoring.contoso.com","Application","WindowsAzureActiveDirectoryIntegratedApp"