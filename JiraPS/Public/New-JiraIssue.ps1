function New-JiraIssue {
    [CmdletBinding( SupportsShouldProcess )]
    param(
        [Parameter( Mandatory )]
        [String]
        $Project,

        [Parameter( Mandatory )]
        [String]
        $IssueType,

        [Parameter( Mandatory )]
        [String]
        $Summary,

        [Int]
        $Priority,

        [String]
        $Description,

        [AllowNull()]
        [AllowEmptyString()]
        [String]
        $Reporter,

        [String[]]
        $Labels,

        [String]
        $Parent,

        [Alias('FixVersions')]
        [String[]]
        $FixVersion,

        [Hashtable]
        $Fields,

        [PSCredential]
        $Credential
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Function started"

        $server = Get-JiraConfigServer -ErrorAction Stop -Debug:$false

        $createmeta = Get-JiraIssueCreateMetadata -Project $Project -IssueType $IssueType -Credential $Credential -ErrorAction Stop -Debug:$false

        $resourceURi = "$server/rest/api/latest/issue"
    }

    process {
        Write-DebugMessage "[$($MyInvocation.MyCommand.Name)] ParameterSetName: $($PsCmdlet.ParameterSetName)"
        Write-DebugMessage "[$($MyInvocation.MyCommand.Name)] PSBoundParameters: $($PSBoundParameters | Out-String)"

        $ProjectObj = Get-JiraProject -Project $Project -Credential $Credential -ErrorAction Stop -Debug:$false
        $IssueTypeObj = Get-JiraIssueType -IssueType $IssueType -Credential $Credential -ErrorAction Stop -Debug:$false

        $requestBody = @{
            "project"   = @{"id" = $ProjectObj.Id}
            "issuetype" = @{"id" = [String] $IssueTypeObj.Id}
            "summary"   = $Summary
        }

        if ($Priority) {
            $requestBody["priority"] = @{"id" = [String] $Priority}
        }

        if ($Description) {
            $requestBody["description"] = $Description
        }

        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey("Reporter")) {
            $requestBody["reporter"] = @{"name" = "$Reporter"}
        }

        if ($Parent) {
            $requestBody["parent"] = @{"key" = $Parent}
        }

        if ($Labels) {
            $requestBody["labels"] = [System.Collections.ArrayList]@()
            foreach ($item in $Labels) {
                $null = $requestBody["labels"].Add($item)
            }
        }

        if ($FixVersion) {
            $requestBody['fixVersions'] = [System.Collections.ArrayList]@()
            foreach ($item in $FixVersion) {
                $null = $requestBody["fixVersions"].Add( @{ name = "$item" } )
            }
        }

        Write-Debug "[$($MyInvocation.MyCommand.Name)] Resolving `$Fields"
        foreach ($_key in $Fields.Keys) {
            $name = $_key
            $value = $Fields.$_key

            if ($field = Get-JiraField -Field $name -Credential $Credential -Debug:$false) {
                # For some reason, this was coming through as a hashtable instead of a String,
                # which was causing ConvertTo-Json to crash later.
                # Not sure why, but this forces $id to be a String and not a hashtable.
                $id = $field.Id
                $requestBody["$id"] = $value
            }
            else {
                $errorItem = [System.Management.Automation.ErrorRecord]::new(
                    ([System.ArgumentException]"Invalid value for Parameter"),
                    'ParameterValue.InvalidFields',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $Fields
                )
                $errorItem.ErrorDetails = "Unable to identify field [$name] from -Fields hashtable. Use Get-JiraField for more information."
                $PSCmdlet.ThrowTerminatingError($errorItem)
            }
        }

        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Validating fields with metadata"
        foreach ($c in $createmeta) {
            Write-Debug "[$($MyInvocation.MyCommand.Name)] Checking metadata for `$c [$c]"
            if ($c.Required) {
                if ($requestBody.ContainsKey($c.Id)) {
                    Write-DebugMessage "[$($MyInvocation.MyCommand.Name)] Required field (id=[$($c.Id)], name=[$($c.Name)]) was provided (value=[$($requestBody.$($c.Id))])"
                }
                else {
                    $errorItem = [System.Management.Automation.ErrorRecord]::new(
                        ([System.ArgumentException]"Invalid or missing value Parameter"),
                        'ParameterValue.CreateMetaFailure',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $Fields
                    )
                    $errorItem.ErrorDetails = "Jira's metadata for project [$Project] and issue type [$IssueType] specifies that a field is required that was not provided (name=[$($c.Name)], id=[$($c.Id)]). Use Get-JiraIssueCreateMetadata for more information."
                    $PSCmdlet.ThrowTerminatingError($errorItem)
                }
            }
            else {
                Write-DebugMessage "[$($MyInvocation.MyCommand.Name)] Non-required field (id=[$($c.Id)], name=[$($c.Name)])"
            }
        }

        $hashtable = @{
            'fields' = ([PSCustomObject]$requestBody)
        }

        $parameter = @{
            URI        = $resourceURi
            Method     = "POST"
            Body       = (ConvertTo-Json -InputObject ([PSCustomObject]$hashtable) -Depth 7)
            Credential = $Credential
        }
        Write-Debug "[$($MyInvocation.MyCommand.Name)] Invoking JiraMethod with `$parameter"
        if ($PSCmdlet.ShouldProcess($Summary, "Creating new Issue on JIRA")) {
            $result = Invoke-JiraMethod @parameter

            # REST result will look something like this:
            # {"id":"12345","key":"IT-3676","self":"http://jiraserver.example.com/rest/api/latest/issue/12345"}
            # This will fetch the created issue to return it with all it'a properties
            Write-Output (Get-JiraIssue -Key $result.Key -Credential $Credential)
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Complete"
    }
}
