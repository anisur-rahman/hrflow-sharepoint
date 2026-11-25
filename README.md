# HRFlow SharePoint Online portal

A demo employee portal for a fictional company, built as code: the pages, navigation, lists, forms, document libraries and branding of a SharePoint Online communication site are defined in JSON and provisioned with PnP PowerShell.

All people, contact details, documents and announcements are fictional. Emails use `example.com` and phone numbers use 555-01xx.

## What it builds

- 14 pages with a grouped menu: HR, IT, Finance, Training, FAQ and Contact
- 5 submission forms backed by SharePoint lists: leave, IT support, expenses, training registration and HR questions
- Employee directory, course list and onboarding checklist
- 4 document libraries with 12 sample Word documents
- 3 news posts
- Black and white theme, header, footer and logo

## Screenshots

Captured from the deployed test site as the site owner, so editing controls are visible. Select a picture to see it full size.

### Home

![Home page](screenshots/home.png)

### Pages

| Human Resources | IT Department | Finance |
|---|---|---|
| <a href="screenshots/hr.png"><img src="screenshots/hr.png" alt="Human Resources" width="260"></a> | <a href="screenshots/it.png"><img src="screenshots/it.png" alt="IT Department" width="260"></a> | <a href="screenshots/finance.png"><img src="screenshots/finance.png" alt="Finance" width="260"></a> |
| **Training** | **FAQ** | **Contact** |
| <a href="screenshots/training.png"><img src="screenshots/training.png" alt="Training" width="260"></a> | <a href="screenshots/faq.png"><img src="screenshots/faq.png" alt="FAQ" width="260"></a> | <a href="screenshots/contact.png"><img src="screenshots/contact.png" alt="Contact" width="260"></a> |
| **Employee Directory** | **Leave Requests** | **Benefits** |
| <a href="screenshots/employee-directory.png"><img src="screenshots/employee-directory.png" alt="Employee Directory" width="260"></a> | <a href="screenshots/leave-requests.png"><img src="screenshots/leave-requests.png" alt="Leave Requests" width="260"></a> | <a href="screenshots/benefits.png"><img src="screenshots/benefits.png" alt="Benefits" width="260"></a> |
| **Onboarding** | **IT Support** | **IT FAQ** |
| <a href="screenshots/onboarding.png"><img src="screenshots/onboarding.png" alt="Onboarding" width="260"></a> | <a href="screenshots/it-support.png"><img src="screenshots/it-support.png" alt="IT Support" width="260"></a> | <a href="screenshots/it-faq.png"><img src="screenshots/it-faq.png" alt="IT FAQ" width="260"></a> |
| **Expenses** |  |  |
| <a href="screenshots/expenses.png"><img src="screenshots/expenses.png" alt="Expenses" width="260"></a> |  |  |

### Forms

| Leave request | IT request | Expense claim |
|---|---|---|
| <a href="screenshots/form-leave-requests.png"><img src="screenshots/form-leave-requests.png" alt="Leave request" width="260"></a> | <a href="screenshots/form-it-support.png"><img src="screenshots/form-it-support.png" alt="IT request" width="260"></a> | <a href="screenshots/form-expenses.png"><img src="screenshots/form-expenses.png" alt="Expense claim" width="260"></a> |
| **Training registration** | **HR question** |  |
| <a href="screenshots/form-training.png"><img src="screenshots/form-training.png" alt="Training registration" width="260"></a> | <a href="screenshots/form-contact.png"><img src="screenshots/form-contact.png" alt="HR question" width="260"></a> |  |

### News

| Company news | Policy update | Training news |
|---|---|---|
| <a href="screenshots/news-denver-office.png"><img src="screenshots/news-denver-office.png" alt="Company news" width="260"></a> | <a href="screenshots/news-remote-work.png"><img src="screenshots/news-remote-work.png" alt="Policy update" width="260"></a> | <a href="screenshots/news-security-training.png"><img src="screenshots/news-security-training.png" alt="Training news" width="260"></a> |

## Files

| File | Purpose |
|---|---|
| `site-config.json` | Pages, menu, lists, form fields, theme and branding |
| `demo-content.json` | Sample list entries and news posts |
| `documents/` | Sample Word documents, one folder per library |
| `site-logo.svg` | Header logo |
| `screenshots/` | Pictures used in this README |
| `deploy.ps1` | Provisions everything above |

## Setup

1. Install PowerShell 7.4 or newer, then run `Install-Module PnP.PowerShell -Scope CurrentUser`.
2. Register an Entra ID app for interactive sign-in and note its client ID:
   ```powershell
   Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "HRFlow Deploy" -Tenant YOUR-TENANT.onmicrosoft.com -SharePointDelegatePermissions "AllSites.FullControl"
   ```
   The script signs in as you. It uses no client secret.
3. Create a communication site for testing. Do not start with your root site.

## Deploy

```powershell
$id   = "YOUR-CLIENT-ID"
$site = "https://YOUR-TENANT.sharepoint.com/sites/HRFlowTest"

./deploy.ps1 -ClientId $id -SiteUrl $site                                      # print the config, change nothing
./deploy.ps1 -ClientId $id -SiteUrl $site -Apply -SetBranding -SeedDemo        # first deployment
./deploy.ps1 -ClientId $id -SiteUrl $site -Apply -UpdatePages -Only Contact    # publish edits to one page
```

| Switch | Effect |
|---|---|
| `-Apply` | Make changes. Without it the script only prints the config. |
| `-UpdatePages` | Rebuild existing pages and clean up menu items to match the config |
| `-Only HR,Contact` | Limit page work to these pages and skip menu changes |
| `-SetBranding` | Set the site title, theme, logo, header and footer |
| `-SeedDemo` | Fill empty lists, upload sample documents and post the demo news |
| `-SetHomepage` | Make HRFlow Home the site homepage |

## How it behaves

- Runs can be repeated. Existing pages, menu items, list entries and documents are skipped unless a switch says otherwise. If a run times out, run it again.
- `-UpdatePages` overwrites text edited in the browser. Pages containing web parts the script does not create are skipped with a warning.
- The theme is applied to the target site only. The tenant theme gallery is not changed.
- Nothing is deleted except menu items that no longer match the config, and only with `-UpdatePages`.

## Limitations

- Developed against one test site with PnP PowerShell 3.5 on macOS. A full deployment to an empty site in a single run has not been tested.
- Forms save list entries. There are no approval workflows or notifications; Power Automate would be the next step.
- Lists inherit site permissions, so anyone with access can see all entries. Do not store real HR data in them.
- Header tagline, tile size and tile layout are limited by what SharePoint's native web parts allow.
