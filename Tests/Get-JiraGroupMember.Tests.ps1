﻿Describe "Get-JiraGroupMember" {

    Import-Module "$PSScriptRoot/../JiraPS" -Force -ErrorAction Stop

    InModuleScope JiraPS {

        . "$PSScriptRoot/Shared.ps1"

        Mock Get-JiraConfigServer {
            'https://jira.example.com'
        }

        # If we don't override this in a context or test, we don't want it to
        # actually try to query a JIRA instance
        Mock Invoke-JiraMethod {
            ShowMockInfo 'Invoke-JiraMethod' 'Method', 'Uri'
            throw "Unidentified call to Invoke-JiraMethod"
        }

        Mock Invoke-JiraMethod -ModuleName JiraPS -ParameterFilter { $Method -eq 'Get' -and $URI -like '*/rest/api/*/group?groupname=testgroup*' } {
            ShowMockInfo 'Invoke-JiraMethod' 'Method', 'Uri'
            ConvertFrom-Json @'
{
    "Name":  "testgroup",
    "RestUrl":  "https://jira.example.com/rest/api/2/group?groupname=testgroup",
    "Size":  2
}
'@
        }

        Mock Get-JiraGroup -ModuleName JiraPS {
            $obj = [PSCustomObject] @{
                'Name'    = 'testgroup'
                'RestUrl' = 'https://jira.example.com/rest/api/2/group?groupname=testgroup'
                'Size'    = 2
            }
            $obj.PSObject.TypeNames.Insert(0, 'JiraPS.Group')
            Write-Output $obj
        }

        Context "Sanity checking" {
            $command = Get-Command -Name Get-JiraGroupMember

            defParam $command 'Group'
            defParam $command 'StartIndex'
            defParam $command 'MaxResults'
            defParam $command 'Credential'
        }

        Context "Behavior testing" {
            Mock Invoke-JiraMethod -ModuleName JiraPS {
                ShowMockInfo 'Invoke-JiraMethod' 'Method', 'Uri'
            }

            Mock Get-JiraUser -ModuleName JiraPS {
                $object = [PSCustomObject] @{
                    'Name' = 'username'
                }
                $object.PSObject.TypeNames.Insert(0, 'JiraPS.User')
                return $object
            }

            It "Obtains members about a provided group in JIRA" {
                { Get-JiraGroupMember -Group testgroup } | Should Not Throw
                Assert-MockCalled -CommandName Invoke-JiraMethod -ModuleName JiraPS -Exactly -Times 1 -Scope It -ParameterFilter { $Method -eq 'Get' -and $URI -like '*/rest/api/*/group?groupname=testgroup&expand=users*' }
            }

            It "Supports the -StartIndex and -MaxResults parameters to page through search results" {
                { Get-JiraGroupMember -Group testgroup -StartIndex 10 -MaxResults 50 } | Should Not Throw
                # Expected: expand=users[10:60] (start index of 10, last index of 10+50)
                # https://docs.atlassian.com/jira/REST/6.4.12/#d2e2307
                # Also, -like doesn't seem to "like" square brackets
                Assert-MockCalled -CommandName Invoke-JiraMethod -ModuleName JiraPS -Exactly -Times 1 -Scope It -ParameterFilter { $Method -eq 'Get' -and $URI -like '*/rest/api/*/group?groupname=testgroup&expand=users*10:60*' }
            }

            It "Returns all issues via looping if -MaxResults is not specified" {

                # In order to test this, we'll need a slightly more elaborate
                # mock that actually returns some data.

                Mock Invoke-JiraMethod -ModuleName JiraPS {
                    ShowMockInfo 'Invoke-JiraMethod' 'Method', 'Uri'
                    ConvertFrom-Json -InputObject @'
{
    "name": "testgroup",
    "self": "https://jira.example.com/rest/api/2/group?groupname=testgroup",
    "users": {
        "size": 2,
        "items": [
            {
                "self": "https://jira.example.com/rest/api/2/user?username=testuser1",
                "key": "testuser1",
                "name": "testuser1",
                "emailAddress": "testuser1@example.com",
                "displayName": "Test User 1",
                "active": true
            },
            {
                "self": "https://jira.example.com/rest/api/2/user?username=testuser2",
                "key": "testuser2",
                "name": "testuser2",
                "emailAddress": "testuser2@example.com",
                "displayName": "Test User 2",
                "active": true
            }
        ],
        "max-results": 50,
        "start-index": 0,
        "end-index": 0
    },
    "expand": "users"
}
'@
                }

                { Get-JiraGroupMember -Group testgroup } | Should Not Throw

                Assert-MockCalled -CommandName Get-JiraGroup -Exactly -Times 1 -Scope It -ParameterFilter { $GroupName -eq 'testgroup' }
                Assert-MockCalled -CommandName Invoke-JiraMethod -Exactly -Times 1 -Scope It -ParameterFilter { $Method -eq 'Get' -and $URI -like '*/rest/api/*/group?groupname=testgroup&expand=users*0:2*' }

            }
        }

        Context "Input testing" {
            It "Accepts a group name for the -Group parameter" {
                { Get-JiraGroupMember -Group testgroup } | Should Not Throw
                Assert-MockCalled -CommandName Invoke-JiraMethod -ModuleName JiraPS -Exactly -Times 1 -Scope It -ParameterFilter { $Method -eq 'Get' -and $URI -like '*/rest/api/*/group?groupname=testgroup&expand=users*' }
            }

            It "Accepts a group object for the -InputObject parameter" {
                $group = Get-JiraGroup -GroupName testgroup

                { Get-JiraGroupMember -Group $group } | Should Not Throw
                Assert-MockCalled -CommandName Invoke-JiraMethod -ModuleName JiraPS -Exactly -Times 1 -Scope It -ParameterFilter { $Method -eq 'Get' -and $URI -like '*/rest/api/*/group?groupname=testgroup&expand=users*' }

                # We called Get-JiraGroup once manually, and it should be
                # called twice by Get-JiraGroupMember.
                Assert-MockCalled -CommandName Get-JiraGroup -Exactly -Times 3 -Scope It
            }
        }
    }
}
