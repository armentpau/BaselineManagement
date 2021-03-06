$script:TestSourceRoot = "$PsScriptRoot"
$script:UnitTestRoot = (Get-ParentItem -Path $script:TestSourceRoot -Filter "unit" -Recurse -Directory).FullName
$script:SourceRoot = (Get-ParentItem -Path $script:TestSourceRoot -Filter "src" -Recurse -Directory).FullName
$script:ParsersRoot = "$script:SourceRoot\Parsers" 
$script:SampleRoot = "$script:UnitTestRoot\..\Samples"

$me = Split-Path -Path $script:TestSourceRoot -Leaf
$Parsers = Get-ChildItem -Filter '*.ps1' -Path (Join-Path -Path $script:ParsersRoot -ChildPath $me)

$Functions = Get-Item -Path (Join-Path -Path $script:SourceRoot -ChildPath "Helpers\Functions.ps1")
$Enumerations = Get-Item -Path (Join-Path -Path $script:SourceRoot -ChildPath "Helpers\Enumerations.ps1")

. $Functions.FullName
. $Enumerations.FullName
foreach ($Parser in $Parsers)
{
    . $Parser.FullName
}

$SamplePOL = Join-Path $script:SampleRoot "Registry.Pol"
$SampleGPTemp = Join-Path $script:SampleRoot "gptTmpl.inf"
$SampleAuditCSV = Join-Path $script:SampleRoot "audit.csv"
$SampleREGXML = Join-Path $script:SampleRoot "Registry.xml"

Import-Module PSDesiredStateConfiguration -Force

Write-Host -ForegroundColor White "GPO Parser Tests" 
    
Describe "Write-GPORegistryXMLData" {
    Mock Write-DSCString -Verifiable { return @{} + $___BoundParameters___ } 

    [xml]$RegistryXML = Get-Content $SampleREGXML

    $Settings = $RegistryXML.RegistrySettings.Registry

    It "Parses Registry XML" {
        $Settings | Should Not Be $Null
    }
    
    # Loop through every registry setting.
    foreach ($Setting in $Settings)
    {
        $Parameters = Write-GPORegistryXMLData -XML $Setting
        Context $Parameters.Name {
            It "Parses Registry XML Data" {
                If ($Parameters.CommentOut.IsPresent)
                {
                    Write-Host -ForegroundColor Green "This Resource was commented OUT for failure to adhere to Standards: Tests are Invalid"
                }
                else
                {
                    $Parameters.Type | Should Be "Registry"
                    [string]::IsNullOrEmpty($Parameters.Parameters.ValueName) | Should Be $false
                    Test-Path -Path $Parameters.Parameters.Key -IsValid | Should Be $true
                    $TypeHash = @{"Binary" = [byte]; "Dword" = [int]; "ExpandString" = [string]; "MultiString" = [string]; "Qword" = [string]; "String" = [string]}
                    ($Parameters.Parameters.ValueType -in @($TypeHash.Keys)) | Should Be $true
                    Write-Host $Parameters.Parameter.ValueType
                    $Parameters.Parameters.ValueData | Should BeOfType $TypeHash[$Parameters.Parameters.ValueType]
                    [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                }
            }
        }
    }
}

Describe "Write-GPOAuditCSVData" {
    Mock Write-DSCString -Verifiable { return @{} + $___BoundParameters___ } 
    $auditData = Import-CSV -Path $SampleAuditCSV

    foreach ($Entry in $auditData)
    {
        $Parameters = Write-GPOAuditCSVData -Entry $Entry

        switch -regex ($Entry."Inclusion Setting")
        {
            "Success and Failure"
            {
                It "Parses SuccessAndFailure separately" {
                    $Parameters.Count | Should Be 2
                }
                                    
                $Success = $Parameters.Where( {$_.Parameters.AuditFlag -eq "Success"})
                $Failure = $Parameters.Where( {$_.Parameters.AuditFlag -eq "Failure"})
                
                Context $Success.Name {
                    It "Separates out the SuccessBlock" {
                        $Success.Type | Should Be AuditPolicySubcategory
                        $Success.Parameters.SubCategory | Should Be $Entry.Name
                        $Success.Parameters.AuditFlag | Should Be "Success"
                        $Success.Parameters.Ensure | Should Be "Present"
                        [string]::IsNullOrEmpty($Success.Name) | Should Be $false
                    }
                }

                Context $Failure.Name {
                    It "Separates out the FailureBlock" {
                        $Failure.Type | Should Be AuditPolicySubcategory
                        $Failure.Parameters.SubCategory | Should Be $Entry.Name
                        $Failure.Parameters.AuditFlag | Should Be "Failure"
                        $Failure.Parameters.Ensure | Should Be "Present"
                        [string]::IsNullOrEmpty($Failure.Name) | Should Be $false
                    }
                }
            }

            "No Auditing"
            {
                It "Parses NoAuditing separately" {
                    $Parameters.Count | Should Be 2
                }
                                    
                $Success = $Parameters.Where( {$_.Parameters.AuditFlag -eq "Success"})
                $Failure = $Parameters.Where( {$_.Parameters.AuditFlag -eq "Failure"})
                
                Context $Success.Name {
                    It "Separates out the SuccessBlock" {
                        $Success.Type | Should Be AuditPolicySubcategory
                        $Success.Parameters.SubCategory | Should Be $Entry.Name
                        $Success.Parameters.AuditFlag | Should Be "Success"
                        $Success.Parameters.Ensure | Should Be "Absent"
                        [string]::IsNullOrEmpty($Success.Name) | Should Be $false
                    }
                }

                Context $Failure.Name {
                    It "Separates out the FailureBlock" {
                        $Failure.Type | Should Be AuditPolicySubcategory
                        $Failure.Parameters.SubCategory | Should Be $Entry.Name
                        $Failure.Parameters.AuditFlag | Should Be "Failure"
                        $Failure.Parameters.Ensure | Should Be "Absent"
                        [string]::IsNullOrEmpty($Failure.Name) | Should Be $false
                    }
                }
            }

            "^(Success|Failure)$"
            {
                Context $Parameters.Name {
                    It "Parses Audit Data" {
                        $Parameters.Type | Should Be AuditPolicySubcategory
                        $Parameters.Parameters.SubCategory | Should Be $Entry.Name
                        $Parameters.Parameters.AuditFlag | Should Be $_
                        $Parameters.Parameters.Ensure | Should Be "Present"
                        [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                    }
                }
            }
        }
        
        switch -regex ($Entry."Exclusion Setting")
        {
            "Success and Failure"
            {
                It "Parses SuccessAndFailure separately" {
                    $Parameters.Count | Should Be 2
                }
                                    
                $Success = $Parameters.Where( {$_.Parameters.AuditFlag -eq "Success"})
                $Failure = $Parameters.Where( {$_.Parameters.AuditFlag -eq "Failure"})
                
                Context $Success.Name {
                    It "Separates out the SuccessBlock" {
                        $Success.Type | Should Be AuditPolicySubcategory
                        $Success.Parameters.SubCategory | Should Be $Entry.Name
                        $Success.Parameters.AuditFlag | Should Be "Success"
                        $Success.Parameters.Ensure | Should Be "Absent"
                        [string]::IsNullOrEmpty($Success.Name) | Should Be $false
                    }
                }

                Context $Failure.Name {
                    It "Separates out the FailureBlock" {
                        $Failure.Type | Should Be AuditPolicySubcategory
                        $Failure.Parameters.SubCategory | Should Be $Entry.Name
                        $Failure.Parameters.AuditFlag | Should Be "Failure"
                        $Failure.Parameters.Ensure | Should Be "Absent"
                        [string]::IsNullOrEmpty($Failure.Name) | Should Be $false
                    }
                }
            }

            "No Auditing"
            {
                # I am not sure how to make sure that "No Auditing" is Excluded or ABSENT. What should it be set to then?
            }

            "^(Success|Failure)$"
            {
                Context $Parameters.Name {
                    It "Parses Audit Data" {
                        $Parameters.Type | Should Be AuditPolicySubcategory
                        $Parameters.Parameters.SubCategory | Should Be $Entry.Name
                        $Parameters.Parameters.AuditFlag | Should Be $_
                        $Parameters.Ensure | Should Be "Absent"
                        [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                    }
                }
            }
        }
    }
}

Describe "Write-GPORegistryPOLData" {
    Mock Write-DSCString -Verifiable { return @{} + $___BoundParameters___ } 
    $registryPolicies = Read-PolFile -Path $SamplePOL

    It "Parses Registry Policies" {
        $registryPolicies | Should Not Be $Null
    }

    foreach ($Policy in $registryPolicies)
    {
        $Parameters = Write-GPORegistryPOLData -Data $Policy
        Context $Parameters.Name {
            It "Parses Registry Data" {
                If ($Parameters.CommentOut.IsPresent)
                {
                    Write-Host -ForegroundColor Green "This Resource was commented OUT for failure to adhere to Standards: Tests are Invalid"
                }
                else
                {
                    $Parameters.Type | Should Be "Registry"
                    Test-Path -Path $Parameters.Parameters.Key -IsValid | Should Be $true
                    $TypeHash = @{"Binary" = [byte]; "Dword" = [int]; "ExpandString" = [string]; "MultiString" = [string]; "Qword" = [string]; "String" = [string]}
                    if ($Parameters.Name.StartsWith("DELVAL"))
                    {
                        if ($ExlusiveFlagAvailable)
                        {
                            $Parameters.Parameters.Ensure | Should Be "Absent"
                        }
                        else
                        {
                            $Parameters.CommentOUT | Should Be $True
                        }
                    }
                    elseif ($Parameters.Name.StartsWith("DEL"))
                    {
                        $Parameters.Parameters.Ensure | Should Be "Absent"
                    }
                    elseif ($Parameters.Parameters.ContainsKey("ValueType"))
                    {
                        ($Parameters.Parameters.ValueType -in @($TypeHash.Keys)) | Should Be $true 
                    }
                    
                    if ($Parameters.Parameters.ContainsKey("ValueData"))
                    {
                        $Parameters.Parameters.ValueData | Should BeOfType $TypeHash[$Parameters.Parameters.ValueType]
                    }

                    [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                }
            }
        }
    }
}
    
Describe "GPtTempl.INF Data" {
    Mock Write-DSCString -Verifiable { return @{} + $___BoundParameters___ } 
    $ini = Get-IniContent $SampleGPTemp

    It "Parses INF files" {
        { Get-IniContent $SampleGPTemp } | Should Not Throw
        $ini | Should Not Be $null
    }

    # Loop through every heading.
    foreach ($key in $ini.Keys)
    {
        # Loop through every setting in the heading.
        foreach ($subKey in $ini[$key].Keys)
        {
            switch ($key)
            {
                "Service General Setting"
                {
                    $Parameters = Write-GPOServiceINFData -Service $subkey -ServiceData $ini[$key][$subKey]
                    Context $Parameters.Name {    
                        It "Parses Service Data" {
                            $Parameters.Type | Should Be "Service"
                        }
                    }
                }

                "Registry Values"
                {
                    $Parameters = Write-GPORegistryINFData -Key $subkey -ValueData $ini[$key][$subKey]
                    Context $Parameters.Name {
                        It "Parses Registry Values" {
                            If ($Parameters.CommentOut.IsPresent)
                            {
                                Write-Host -ForegroundColor Green "This Resource was commented OUT for failure to adhere to Standards: Tests are Invalid"
                            }
                            else
                            {
                                $Parameters.Type | Should Be "Registry"
                                [string]::IsNullOrEmpty($Parameters.Parameters.ValueName) | Should Be $false
                                Test-Path -Path $Parameters.Parameters.Key -IsValid | Should Be $true
                                $TypeHash = @{"Binary" = [byte]; "Dword" = [int]; "ExpandString" = [string]; "MultiString" = [string]; "Qword" = [string]; "String" = [string]}
                                ($Parameters.Parameters.ValueType -in @($TypeHash.Keys)) | Should Be $true
                                $Parameters.Parameters.ValueData | Should BeOfType $TypeHash[$Parameters.Parameters.ValueType]
                                [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                            }
                        }
                    }
                }

                "File Security"
                {
                    $Parameters = Write-GPOFileSecurityINFData -Path $subkey -ACLData $ini[$key][$subKey]
                    Context $Parameters.Name {
                        It "Parses File ACL Data" {
                            $Parameters.Type | Should Be ACL
                            [String]::IsNullOrEmpty($Parameters.Parameters.DACLString) | Should Be $false
                            Test-PAth -Path "$($Parameters.Parameters.Path)" -IsValid | Should Be $true
                            [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                        }
                    }
                }
            
                "Privilege Rights"
                {
                    $Parameters = Write-GPOPrivilegeINFData -Privilege $subkey -PrivilegeData $ini[$key][$subKey]
                    Context $Parameters.Name {
                        It "Parses Privilege Data" {
                            $Parameters.Type | Should Be "UserRightsAssignment"
                            [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                            $UserRightsHash.Values -contains $Parameters.Parameters.Policy | Should Be $true
                        }
                    }
                }

                "Kerberos Policy"
                {
                    $Parameters = Write-GPOSecuritySettingINFData -Key $subKey -SecurityData $ini[$key][$subkey]
                    Context $Parameters.Name {
                        It "Parses Kerberos Data" {
                            $Parameters.Type | Should Be "SecuritySetting"
                            [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                            $SecuritySettings -contains $Parameters.Parameters.Name | Should Be $true
                            $Parameters.Parameters.ContainsKey($Parameters.Parameters.Name) | Should Be $true
                        }
                    }
                }
            
                "Registry Keys"
                {
                    $Parameters = Write-GPORegistryACLINFData -Path $subkey -ACLData $ini[$key][$subKey]
                    
                    Context $Parameters.Name {
                        It "Parses Registry ACL Data" {
                            [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                            Test-Path -Path $Parameters.Parameters.Path -IsValid | Should Be $true
                            [string]::IsNullOrEmpty($Parameters.Parameters.DACLString) | SHould Be $false
                        }
                    }
                }
            
                "System Access"
                {
                    $Parameters = Write-GPOSecuritySettingINFData -Key $subKey -SecurityData $ini[$key][$subkey]
                    Context $Parameters.Name {                        
                        It "Parses System Access Settings" {
                            $Parameters.Type | Should Be "SecuritySetting"
                            [string]::IsNullOrEmpty($Parameters.Name) | Should Be $false
                            $SecuritySettings -contains $Parameters.Parameters.Name | Should Be $true
                            $Parameters.Parameters.ContainsKey($Parameters.Parameters.Name) | Should Be $true
                        }
                    }
                }

                "Event Auditing"
                {

                }
            }
        }
    }
}
