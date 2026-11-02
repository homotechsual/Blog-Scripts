BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'OneDriveArchive.psm1') -Force
    $BulkScript = Join-Path $PSScriptRoot 'Invoke-OneDriveArchiveBulk.ps1'
    $SingleScript = Join-Path $PSScriptRoot 'Invoke-OneDriveArchive.ps1'
}

Describe 'Display-name archive folders' {
    BeforeEach {
        Mock Import-Module {}
        Mock Write-OneDriveArchiveLog {} -ModuleName OneDriveArchive
        Mock Resolve-OneDriveArchiveCredential {
            [PSCustomObject]@{ ClientId = 'test'; ClientSecret = 'test' }
        }
        Mock Resolve-OneDriveArchiveTenantId { 'test-tenant' }
        Mock Connect-OneDriveArchiveGraph {}
        Mock Resolve-OneDriveArchiveDestination {
            [PSCustomObject]@{ DriveId = 'destination'; DriveName = 'Documents' }
        }
        Mock Wait-OneDriveArchiveCopy { $Items }
        InModuleScope OneDriveArchive {
            $script:Headers = @{ Authorization = 'test' }
        }
        Mock Invoke-RestMethod -ModuleName OneDriveArchive {
            param($Uri, $Method, $Body)
            if ($Method -eq 'POST') {
                $Folder = $Body | ConvertFrom-Json
                return [PSCustomObject]@{ id = 'folder-id'; name = $Folder.name }
            }
            if ($Uri -like '*?$select=displayName') {
                return [PSCustomObject]@{ displayName = "Morgan O'Test" }
            }
            if ($Uri -like '*/users/*/drives') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'source'; name = 'OneDrive' }) }
            }
            if ($Uri -like '*/drives/source/root/children') {
                return [PSCustomObject]@{ value = @([PSCustomObject]@{ id = 'item-id'; name = 'Documents' }) }
            }
            throw "Unexpected request: $Method $Uri"
        }
        Mock Invoke-WebRequest -ModuleName OneDriveArchive {
            [PSCustomObject]@{ Headers = @{ Location = 'https://example.test/monitor' } }
        }
        $CopyParameters = @{
            GraphBase = 'https://graph.microsoft.com/v1.0'
            SourceUPN = 'mc@contoso.com'
            DestDriveId = 'destination'
        }
        $RunParameters = @{
            ClientId = 'test'
            ClientSecret = 'test'
            DestSiteHost = 'contoso.sharepoint.com'
            DestSitePath = '/sites/archive'
        }
    }

    It 'uses the actual display name instead of the email prefix' {
        $Job = Start-OneDriveArchiveCopy @CopyParameters
        $Job.DestFolderName | Should -BeExactly "Morgan O'Test"
        $Job.DestFolderId | Should -Be 'folder-id'
        $Job.Items.Count | Should -Be 1
        $Job.Items[0].Status | Should -Be 'pending'
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://graph.microsoft.com/v1.0/users/mc%40contoso.com?$select=displayName'
        }
        Should -Invoke Invoke-WebRequest -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Copy = $Body | ConvertFrom-Json
            $Copy.parentReference.id -eq 'folder-id' -and $Copy.name -eq 'Documents'
        }
    }

    It 'preserves an explicit folder name and skips user lookup' {
        $Job = Start-OneDriveArchiveCopy @CopyParameters -DestFolderName 'Custom archive'
        $Job.DestFolderName | Should -BeExactly 'Custom archive'
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 0 -Exactly -ParameterFilter {
            $Uri -like '*?$select=displayName'
        }
    }

    It 'resolves a display name for whitespace-only overrides' {
        (Start-OneDriveArchiveCopy @CopyParameters -DestFolderName '  ').DestFolderName |
            Should -BeExactly "Morgan O'Test"
    }

    It 'encodes special characters in the UPN' {
        $CopyParameters.SourceUPN = 'guest_contoso.com#EXT#@tenant.onmicrosoft.com'
        Start-OneDriveArchiveCopy @CopyParameters | Out-Null
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://graph.microsoft.com/v1.0/users/guest_contoso.com%23EXT%23%40tenant.onmicrosoft.com?$select=displayName'
        }
    }

    It 'records the actual Graph folder name after conflict renaming' {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive {
            [PSCustomObject]@{ id = 'folder-id'; name = "Morgan O'Test 1" }
        } -ParameterFilter { $Method -eq 'POST' }
        (Start-OneDriveArchiveCopy @CopyParameters).DestFolderName | Should -BeExactly "Morgan O'Test 1"
    }

    It 'fails before creating a folder if lookup is denied' {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive { throw '403 Forbidden' } -ParameterFilter {
            $Uri -like '*?$select=displayName'
        }
        { Start-OneDriveArchiveCopy @CopyParameters } | Should -Throw '*User.Read.All*403 Forbidden*'
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'fails before creating a folder for a missing or blank display name: <Label>' -ForEach @(
        @{ Label = 'missing property'; Response = [PSCustomObject]@{ id = 'user-id' } }
        @{ Label = 'null'; Response = [PSCustomObject]@{ displayName = $null } }
        @{ Label = 'whitespace'; Response = [PSCustomObject]@{ displayName = '  ' } }
    ) {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive { $Response } -ParameterFilter {
            $Uri -like '*?$select=displayName'
        }
        { Start-OneDriveArchiveCopy @CopyParameters } | Should -Throw '*No display name returned*'
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'sanitizes display names without changing their capitalization or punctuation' {
        ConvertTo-OneDriveArchiveFolderName -DisplayName '  McDonald, Jo: IT/Support\Ops?*<>"|. ' |
            Should -BeExactly 'McDonald, Jo_ IT_Support_Ops______'
        ConvertTo-OneDriveArchiveFolderName -DisplayName "Morgan O'Test" | Should -BeExactly "Morgan O'Test"
        ConvertTo-OneDriveArchiveFolderName -DisplayName 'Morgan . . ' | Should -BeExactly 'Morgan'
        { ConvertTo-OneDriveArchiveFolderName -DisplayName ' ... ' } | Should -Throw '*valid folder name*'
    }

    It 'uses display names in a manual bulk run without a CSV' {
        $StatePath = Join-Path $TestDrive 'manual.json'
        & $BulkScript @RunParameters -SourceUPN 'mc@contoso.com', 'other@contoso.com' -StateFilePath $StatePath
        $Jobs = @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
        $Jobs.Count | Should -Be 2
        $Jobs[0].DestFolderName | Should -BeExactly "Morgan O'Test"
        $Jobs[1].DestFolderName | Should -BeExactly "Morgan O'Test"
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 2 -Exactly -ParameterFilter {
            $Uri -like '*?$select=displayName'
        }
    }

    It 'uses a display name for a one-off bulk invocation' {
        $StatePath = Join-Path $TestDrive 'one-off.json'
        & $BulkScript @RunParameters -SourceUPN 'mc@contoso.com' -StateFilePath $StatePath
        (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json).DestFolderName |
            Should -BeExactly "Morgan O'Test"
    }

    It 'honors explicit CSV names and resolves blank names' {
        $CsvPath = Join-Path $TestDrive 'users.csv'
        @(
            [PSCustomObject]@{ SourceUPN = 'mc@contoso.com'; DestFolderName = 'Explicit archive' }
            [PSCustomObject]@{ SourceUPN = 'other@contoso.com'; DestFolderName = '' }
        ) | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
        $StatePath = Join-Path $TestDrive 'csv.json'
        & $BulkScript @RunParameters -CsvPath $CsvPath -StateFilePath $StatePath
        $Jobs = @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
        $Jobs[0].DestFolderName | Should -BeExactly 'Explicit archive'
        $Jobs[1].DestFolderName | Should -BeExactly "Morgan O'Test"
    }

    It 'records lookup failures and continues processing other users' {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive { throw '403 Forbidden' } -ParameterFilter {
            $Uri -like '*/users/mc%40contoso.com?$select=displayName'
        }

        $StatePath = Join-Path $TestDrive 'partial.json'
        & $BulkScript @RunParameters -SourceUPN 'mc@contoso.com', 'other@contoso.com' -StateFilePath $StatePath
        $Jobs = @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
        $Jobs.Count | Should -Be 2
        $Jobs[0].Error | Should -BeLike '*403 Forbidden*'
        $Jobs[0].DestFolderId | Should -BeNullOrEmpty
        $Jobs[1].DestFolderName | Should -BeExactly "Morgan O'Test"
    }

    It 'resolves names for CSV files containing only the required UPN column' {
        $CsvPath = Join-Path $TestDrive 'minimal.csv'
        [PSCustomObject]@{ SourceUPN = 'mc@contoso.com' } | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
        $StatePath = Join-Path $TestDrive 'minimal.json'
        & $BulkScript @RunParameters -CsvPath $CsvPath -StateFilePath $StatePath
        (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json).DestFolderName |
            Should -BeExactly "Morgan O'Test"
    }

    It 'uses display names in the single-user entry point unless overridden' {
        & $SingleScript @RunParameters -SourceUPN 'mc@contoso.com'
        & $SingleScript @RunParameters -SourceUPN 'mc@contoso.com' -DestFolderName 'Legacy archive'
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*?$select=displayName'
        }
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and ($Body | ConvertFrom-Json).name -eq 'Legacy archive'
        }
    }

    It 'handles an empty OneDrive without failing under strict mode' {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive {
            [PSCustomObject]@{ value = @() }
        } -ParameterFilter { $Uri -like '*/drives/source/root/children' }

        $Job = & $SingleScript @RunParameters -SourceUPN 'mc@contoso.com'
        $Job.Items.Count | Should -Be 0
        $Job.DestFolderId | Should -Be 'folder-id'
        Should -Invoke Invoke-WebRequest -ModuleName OneDriveArchive -Times 0 -Exactly
    }

    It 'records missing monitor URLs as errors instead of confirming success' {
        Mock Invoke-WebRequest -ModuleName OneDriveArchive {
            [PSCustomObject]@{ Headers = @{}; StatusCode = 202 }
        }
        $Job = Start-OneDriveArchiveCopy @CopyParameters
        $Job.Items[0].Status | Should -Be 'error'
        $Job.Items[0].Error | Should -BeLike '*Completion cannot be confirmed*'
    }

    It 'normalizes an array-valued Location header and uses the copy conflict query parameter' {
        Mock Invoke-WebRequest -ModuleName OneDriveArchive {
            [PSCustomObject]@{ Headers = @{ Location = @('https://example.test/monitor') } }
        }
        $Job = Start-OneDriveArchiveCopy @CopyParameters
        $Job.Items[0].MonitorUrl | Should -BeOfType ([string])
        $Job.Items[0].MonitorUrl | Should -Be 'https://example.test/monitor'
        Should -Invoke Invoke-WebRequest -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*/copy?@microsoft.graph.conflictBehavior=rename' -and
            ($Body | ConvertFrom-Json).PSObject.Properties.Name -notcontains '@microsoft.graph.conflictBehavior'
        }
    }

    It 'keeps item queue failures and sharing failures in the bulk state file' {
        Mock Invoke-WebRequest -ModuleName OneDriveArchive { throw '429 Too Many Requests' }
        Mock Grant-OneDriveArchiveFolderAccess { throw 'Invitation denied' }
        $StatePath = Join-Path $TestDrive 'errors.json'

        & $BulkScript @RunParameters -SourceUPN 'mc@contoso.com' -ShareWithUPN 'manager@contoso.com' -StateFilePath $StatePath
        $Json = Get-Content -LiteralPath $StatePath -Raw
        $Json.TrimStart().StartsWith('[') | Should -BeTrue
        $Job = @($Json | ConvertFrom-Json)[0]
        $Job.Items[0].Status | Should -Be 'error'
        $Job.Items[0].Error | Should -BeLike '*429*'
        $Job.ShareError | Should -Be 'Invitation denied'
    }

    It 'does not overwrite an existing state file or queue duplicate copies' {
        $StatePath = Join-Path $TestDrive 'existing.json'
        'keep this state' | Set-Content -LiteralPath $StatePath
        { & $BulkScript @RunParameters -SourceUPN 'mc@contoso.com' -StateFilePath $StatePath } |
            Should -Throw '*State file already exists*'
        (Get-Content -LiteralPath $StatePath -Raw).Trim() | Should -Be 'keep this state'
        Should -Invoke Invoke-WebRequest -ModuleName OneDriveArchive -Times 0 -Exactly
    }

    It 'saves the first user before queuing the next user' {
        $StatePath = Join-Path $TestDrive 'incremental.json'
        Mock Start-OneDriveArchiveCopy {
            if ($SourceUPN -eq 'other@contoso.com') {
                $Saved = @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
                $Saved.Count | Should -Be 1
                $Saved[0].SourceUPN | Should -Be 'mc@contoso.com'
            }
            [PSCustomObject]@{
                SourceUPN = $SourceUPN
                DestFolderName = 'Archive'
                DestFolderId = 'folder-id'
                Items = @()
            }
        }
        & $BulkScript @RunParameters -SourceUPN 'mc@contoso.com', 'other@contoso.com' -StateFilePath $StatePath
        @(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json).Count | Should -Be 2
        Should -Invoke Start-OneDriveArchiveCopy -Times 2 -Exactly
    }

    It 'returns failed and pending single-user copies without a misleading success message' {
        Mock Wait-OneDriveArchiveCopy {
            @(
                [PSCustomObject]@{ Name = 'Failed'; Status = 'failed'; Error = 'Copy failed' }
                [PSCustomObject]@{ Name = 'Pending'; Status = 'pending'; MonitorUrl = 'https://example.test/monitor' }
            )
        }
        Mock Write-OneDriveArchiveLog {}
        $Job = & $SingleScript @RunParameters -SourceUPN 'mc@contoso.com'
        $Job.Items.Count | Should -Be 2
        Should -Invoke Write-OneDriveArchiveLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Message -like '*0 completed, 1 failed, 1 pending*'
        }
        Should -Invoke Write-OneDriveArchiveLog -Times 0 -Exactly -ParameterFilter {
            $Message -like 'All * copy job(s) completed*'
        }
    }
}

Describe 'Copy monitoring and status reporting' {
    BeforeEach {
        Mock Import-Module {}
        Mock Write-OneDriveArchiveLog {} -ModuleName OneDriveArchive
        Mock Resolve-OneDriveArchiveCredential {
            [PSCustomObject]@{ ClientId = 'test'; ClientSecret = 'test' }
        }
        Mock Resolve-OneDriveArchiveTenantId { 'test-tenant' }
        Mock Connect-OneDriveArchiveGraph {}
        Mock Start-Sleep {} -ModuleName OneDriveArchive
        InModuleScope OneDriveArchive {
            $script:Headers = @{ Authorization = 'test' }
        }
        $Item = [PSCustomObject]@{
            Name = 'Documents'
            MonitorUrl = 'https://example.test/monitor'
            Status = 'pending'
        }
        $StatusScript = Join-Path $PSScriptRoot 'Get-OneDriveArchiveStatus.ps1'
    }

    It 'records successful copies and clears previous polling errors' {
        $Item | Add-Member -NotePropertyName PollError -NotePropertyValue 'Previous timeout'
        Mock Invoke-RestMethod -ModuleName OneDriveArchive {
            [PSCustomObject]@{ status = 'completed' }
        }
        $Result = @(Update-OneDriveArchiveCopyStatus -Items @($Item))
        $Result[0].Status | Should -Be 'completed'
        $Result[0].PSObject.Properties.Name | Should -Not -Contain 'PollError'
    }

    It 'keeps a running copy pending: <Status>' -ForEach @(
        @{ Status = 'notStarted' }
        @{ Status = 'inProgress' }
        @{ Status = 'updating' }
        @{ Status = 'waiting' }
        @{ Status = 'deletePending' }
    ) {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive {
            [PSCustomObject]@{ status = $Status }
        }
        (Update-OneDriveArchiveCopyStatus -Items @($Item)).Status | Should -Be 'pending'
    }

    It 'retains Graph error details for a terminal failure: <Status>' -ForEach @(
        @{ Status = 'failed' }
        @{ Status = 'deleteFailed' }
    ) {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive {
            [PSCustomObject]@{
                status = $Status
                error = [PSCustomObject]@{ code = 'accessDenied'; message = 'Copy denied' }
            }
        }
        $Result = Update-OneDriveArchiveCopyStatus -Items @($Item)
        $Result.Status | Should -Be 'failed'
        ($Result.Error | ConvertFrom-Json).code | Should -Be 'accessDenied'
        Should -Invoke Write-OneDriveArchiveLog -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Message -like '*Copy failed*'
        }
    }

    It 'records polling failures without claiming completion or discarding the monitor URL' {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive { throw '503 Service Unavailable' }
        $Result = Update-OneDriveArchiveCopyStatus -Items @($Item)
        $Result.Status | Should -Be 'pending'
        $Result.PollError | Should -BeLike '*503*'
        $Result.MonitorUrl | Should -Be 'https://example.test/monitor'
        Should -Invoke Write-OneDriveArchiveLog -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Message -like '*Status remains pending*'
        }
    }

    It 'reports an invalid monitor response instead of treating it as successful: <Label>' -ForEach @(
        @{ Label = 'missing status'; Response = [PSCustomObject]@{ percentageComplete = 100 } }
        @{ Label = 'unknown status'; Response = [PSCustomObject]@{ status = 'unexpected' } }
    ) {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive { $Response }
        $Result = Update-OneDriveArchiveCopyStatus -Items @($Item)
        $Result.Status | Should -Be 'pending'
        $Result.PollError | Should -Not -BeNullOrEmpty
    }

    It 'does not re-poll terminal items' {
        $Item.Status = 'failed'
        Mock Invoke-RestMethod -ModuleName OneDriveArchive { throw 'Should not be called' }
        (Update-OneDriveArchiveCopyStatus -Items @($Item)).Status | Should -Be 'failed'
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 0 -Exactly
    }

    It 'uses a valid progress percentage for mixed initial and final failures' {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive {
            [PSCustomObject]@{ status = 'failed' }
        }
        Mock Write-Progress {} -ModuleName OneDriveArchive
        $Items = @(
            [PSCustomObject]@{ Name = 'Queue error'; Status = 'error' }
            $Item
        )
        $Result = @(Wait-OneDriveArchiveCopy -Items $Items)
        $Result.Count | Should -Be 2
        Should -Invoke Write-Progress -ModuleName OneDriveArchive -Times 1 -Exactly -ParameterFilter {
            $Id -eq 3 -and $PercentComplete -eq 100 -and -not $Completed
        }
    }

    It 'returns pending jobs when local polling times out' {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive { throw 'Should not be called' }
        (Wait-OneDriveArchiveCopy -Items @($Item) -TimeoutMinutes 0).Status | Should -Be 'pending'
        Should -Invoke Invoke-RestMethod -ModuleName OneDriveArchive -Times 0 -Exactly
    }

    It 'persists polling errors and preserves array-shaped state for one user' {
        Mock Invoke-RestMethod -ModuleName OneDriveArchive { throw '503 Service Unavailable' }
        $StatePath = Join-Path $TestDrive 'status.json'
        $Job = [PSCustomObject]@{
            SourceUPN = 'alex@contoso.com'
            DestSiteHost = 'contoso.sharepoint.com'
            DestSitePath = '/sites/archive'
            DestFolderName = 'Alex'
            Items = @($Item)
        }
        ConvertTo-Json -InputObject @($Job) -Depth 10 | Set-Content -LiteralPath $StatePath
        & $StatusScript -ClientId 'test' -ClientSecret 'test' -StateFilePath $StatePath | Out-String | Out-Null
        $Json = Get-Content -LiteralPath $StatePath -Raw
        $Json.TrimStart().StartsWith('[') | Should -BeTrue
        $Saved = @($Json | ConvertFrom-Json)[0]
        $Saved.Items.Count | Should -Be 1
        $Saved.Items[0].Status | Should -Be 'pending'
        $Saved.Items[0].PollError | Should -BeLike '*503*'
        $Saved.PSObject.Properties.Name | Should -Not -Contain 'Error'
        $Saved.PSObject.Properties.Name | Should -Not -Contain 'ShareError'
    }
}

Describe 'Bulk template creation' {
    It 'creates the documented columns without opening an application' {
        $Path = Join-Path $TestDrive 'users.csv'
        & (Join-Path $PSScriptRoot 'New-OneDriveArchiveBulkTemplate.ps1') -Path $Path -NoOpen
        $Row = Import-Csv -LiteralPath $Path
        $Row.PSObject.Properties.Name | Should -Be @('SourceUPN', 'DestFolderName', 'DestSiteHost', 'DestSitePath', 'ShareWithUPN')
        $Row.SourceUPN | Should -Be 'user@contoso.com'
    }

    It 'refuses to overwrite an existing user list' {
        $Path = Join-Path $TestDrive 'existing.csv'
        'Keep my users' | Set-Content -LiteralPath $Path
        { & (Join-Path $PSScriptRoot 'New-OneDriveArchiveBulkTemplate.ps1') -Path $Path -NoOpen } |
            Should -Throw '*Template path already exists*'
        (Get-Content -LiteralPath $Path -Raw).Trim() | Should -Be 'Keep my users'
    }
}
