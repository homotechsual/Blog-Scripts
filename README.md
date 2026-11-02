# Blog Scripts
Repository holding scripts from my blog at https://homotechsual.dev

My [Docusaurus](https://docusaurus.io) powered blog uses the [Christian Bromann's Docusaurus Theme GitHub Code Block](https://github.com/christian-bromann/docusaurus-theme-github-codeblock/) to reference scripts directly from this GitHub repository.

## OneDrive archiving

The [OneDrive archive scripts](./Microsoft%20365/OneDrive/Archive/) copy a user's OneDrive contents into a SharePoint site's default document library using Microsoft Graph. Keep the entry-point scripts and `OneDriveArchive.psm1` together. Source content is not deleted; the workflow is a content copy, not a backup or compliance-retention system.

Run the accompanying mocked tests with Pester 5 or later:

```powershell
Invoke-Pester -Path '.\Microsoft 365\OneDrive\Archive\OneDriveArchive.Tests.ps1'
```
