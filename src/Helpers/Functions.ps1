#region DSC Strings
# Create a variable so we can detect conflicts in the Configuration.
New-Variable -Name GlobalConflictEngine -Value @{} -Option AllScope -Scope Script -Force
$GlobalConflictEngine = @{}

#Create a variable so we can detect conflicts in the names in the configuration.
New-Variable -Name GlobalNameConflictEngine -Value @{ } -Option AllScope -Scope Script -Force
$GlobalNameConflictEngine = @{}

# Create a variable to track every resource processed for Summary Data.
New-Variable -Name ProcessingHistory -Value @{} -Option AllScope -Scope Script -Force
$ProcessingHistory = @{}

# Global Flag to determine if correct Registry resource is available.
New-Variable -Name ExclusiveFlagAvailable -Value $false -Option AllScope -Scope Script -Force
$ExclusiveFlagAvailable = $false

Function Add-ProcessingHistory
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Type,
        
        [switch]$Conflict,
        [switch]$Disabled,
        [switch]$ParsingError,
        [switch]$ResourceNotFound
    )

    # If we do not have a processing history entry for this type, set it to a blank array.
    # Have to do this here, because they may have forgotten do import the module so we cannot assume only Resources specified in the Import-Module.
    if (!$ProcessingHistory.ContainsKey($Type))
    {
        $ProcessingHistory[$Type] = @()
    }

    # Add this resource to the processing history.
    $ProcessingHistory[$Type] += @{Name = $Name; Conflict = $Conflict; Disabled = $Disabled; ResourceNotFound = $ResourceNotFound;ParsingError = $ParsingError}        
}

Function Test-Conflicts 
{
    [OutputType([bool])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [switch]$CommentOut,
        
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$Resource
    )

    # Set our conflict variables up.
    $GlobalConflict = $false
    $ResourceNotFound = $false
    
    $Conflict = @()
    $ResourceKeys = @()
    # Determine if we have already processed a Resource Block of this type.
    if ($Script:GlobalConflictEngine.ContainsKey($Type))
    {
        
        # Loop through every Resource definition of this type.
        foreach ($hashtable in $Script:GlobalConflictEngine[$Type])
        {
            $Conflict = @()
            $ResourceKeys = @()

            # Loop through every Key/Value Pair in the Resource definition to see if they match the current one.
            foreach ($KeyPair in $hashtable.GetEnumerator()) 
            {
                # Add the test result to our Conflict Array.
                $Conflict += $KeyPair.Value -eq $Resource[$KeyPair.Name]
                # Need to store which Key/Value Pairs we checked.
                $ResourceKeys += $KeyPair.Name
            }
			
			# If we found a conflict.
			<#if ($Name -like "*ACL(*")
			{
				Wait-Debugger
			}#>
			
			if ($script:GlobalNameConflictEngine.get_item($Name))
			{
				Write-Verbose "Detected conflicting name $($Name).  Commenting Out Block"
				$GlobalConflict = $true
				$conflictOnName = $true
				break
			}
			if ($ResourceKeys.Count -gt 0 -and $Conflict -notcontains $false)
			{
				#Wait-Debugger
                Write-Verbose "Detected Potential Conflict in $Name. Commenting Out Block"
                $GlobalConflict = $true
                break
            }
        }
    }
    else
    {
        Write-Warning "Write-DSCString: DSC Module ($Type) not found on System.  Please re-run the conversion when the module is available."
        $ResourceNotFound = $true
    }

    if (!$GlobalConflict) # Add this Resources Key/Value pairs to the collective.
    {
        $tmpHash = @{}
        foreach ($Key in $ResourceKeys)
        {
            $tmpHash[$key] = $Resource[$key]
		}
		$script:GlobalNameConflictEngine.add($Name, $name) #add the name to the collective
        $Script:GlobalConflictEngine[$Type] += $tmpHash
    }
    
    # Add this resource to the processing history.
    Add-ProcessingHistory -Type $Type -Name $Name -Conflict:$GlobalConflict -Disabled:$CommentOut -ResourceNotFound:$ResourceNotFound

    return ($GlobalConflict -or $ResourceNotFound -or $CommentOut)
}

Function Get-Tabs
{
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory = $true)]
        [int]$Tabs
    )
    (1..$Tabs) | ForEach-Object {"`t"}
}

Function Write-DSCStringKeyPair
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [int]$Tabs,

        [Parameter(Mandatory = $true)]
        $Value
    )
    
    $DSCString = ""
    
    if ($Value -eq $null)
    {
        # Do not allow $null Values
        return "# `n$(Get-Tabs $Tabs)$($key) = $null"
    }
    
    # Start the Resource Key/Value Pair.
    $DSCString += "`n$(Get-Tabs $Tabs)$($key) = "
    $Separator = ", "
    # If the Value is an array, increase the tab stops and add the array operators.
    if ($Value -is [Array]) 
    {
        $DSCString += "@("
        $Tabs++
    }

    # Treat the value like an array, even if it's an array of 1. It simplifies the parsing.
    for ($i = 0; $i -lt @($Value).Count; $i++)
    {
        $tmpValue = @($Value)[$i]
        switch ($tmpValue)
        {
            {$_ -is [System.String]} 
            {
                Try
                {
                    Invoke-Expression $("`$variable = '" + $_.TrimStart("'").TrimEnd("'").TrimStart('"').TrimEnd('"') + "'") | Out-Null
                    $DSCString += "'$([string]::new($_.TrimStart("'").TrimEnd("'").TrimStart('"').TrimEnd('"').Trim()))'" 
                }
                Catch
                {
                    # Parsing Error
                    $DSCString += "@'`n$($_.Trim("'").TrimStart("'").TrimEnd("'").TrimStart('"').TrimEnd('"'))`n'@" 
                }
            }
            
            {$_ -is [System.Boolean]} 
            {
                $DSCString += "`$$([string]([bool]$_))" 
            }

            {$_ -is [System.Collections.Hashtable]} 
            {
                $identifier = "@"
                if ($_.ContainsKey("EmbeddedInstance"))
                {
                    $identifier = $_.EmbeddedInstance
                    $Separator = ";"
                    $_.Remove("EmbeddedInstance") | Out-Null
                }
                
                if ($Value -is [Array])
                {
                    $DSCString += "`n$(Get-Tabs $Tabs)"
                }

                $DSCString += "$identifier"
                $Tabs += 2
                $DSCString += "`n$(Get-Tabs $Tabs){"
                $Tabs++
                foreach ($keypair in $_.GetEnumerator())
                {
                    $DSCString += Write-DSCStringKeyPair -Key $Keypair.Name -Value $Keypair.Value -Tabs $Tabs
                }
                $Tabs--
                $DSCString += "`n$(Get-Tabs $Tabs)}"
                $Tabs -= 2
            }

            Default
            {
                $DSCString += "$($_)" 
            }
        }

        if ((@($Value).Count - $i) -gt 1)
        {
            $DSCString += $Separator
        }
    }
        
    # If the value was an array, close up the array and decrement the tab stops.
    if ($Value -is [Array]) 
    {
        $Tabs--
        $DSCString += "`n$(Get-Tabs $Tabs))"
    }

    return $DSCString
}



# This is the function that makes it all go. It has a variety of parameter sets which can be tricky to use.
# Each of the Switches tell the function what type of Code block it is creating.  
# The additional parameters to the set are what determine the contents of the block.
# This Function takes the input and properly formats it with Tabs and Newlines so it looks properly formatted.
# It also has a built in Conflict detection engine. 
# If it detects that a Resource with the Same REQUIRED values was already processed it will COMMENT OUT subsequent resource blocks with the same values.
# The Function also has logic to arbitrarily comment out a resource block if necessary (like disabled resources).
# The function also provides functionality to comment Code Blocks if comments are available.
Function Write-DSCString
{
    [CmdletBinding()]
    [OutputType([String])]
    param
    (
        # Configuration Block
        [Parameter(Mandatory = $true, ParameterSetName = "Configuration")]
        [switch]$Configuration,

        # Resource Block
        [Parameter(Mandatory = $true, ParameterSetName = "Resource")]
        [switch]$Resource,

        # Import-Module line.
        [Parameter(Mandatory = $true, ParameterSetName = "ModuleImport")]
        [switch]$ModuleImport,

        # Node Block.
        [Parameter(Mandatory = $true, ParameterSetName = "Node")]
        [switch]$Node,

        # Close out the configuration block.
        [Parameter(ParameterSetName = "CloseConfigurationBlock")]
        [switch]$CloseConfigurationBlock,

        # Close the Node Block.
        [Parameter(ParameterSetName = "CloseNodeBlock")]
        [switch]$CloseNodeBlock,

        # Invoke the Configuration (to create the MOF).
        [Parameter(Mandatory = $true, ParameterSetName = "InvokeConfiguration")]
        [switch]$InvokeConfiguration,

        # This will be the Name of the Configuration Block or Node block or Resource Block.
        [Parameter(Mandatory = $true, ParameterSetName = "Configuration")]
        [Parameter(Mandatory = $true, ParameterSetName = "InvokeConfiguration")]
        [Parameter(Mandatory = $true, ParameterSetName = "Node")]
        [Parameter(Mandatory = $true, ParameterSetName = "Resource")]
        [string]$Name,

        # This is the TYPE to be used with Resource Blocks (Regisry, Service, etc.).
        [Parameter(Mandatory = $true, ParameterSetName = "Resource")]
        [string]$Type,

        # This is an Array of ModuleNames to import.
        [Parameter(Mandatory = $true, ParameterSetName = "ModuleImport")]
        [string[]]$ModuleName,

        # This is a hashtable of Keys/Values for a Resource Block.
        [Parameter(Mandatory = $true, ParameterSetName = "Resource")]
        [hashtable]$Parameters,
        
        # This determines whether or not to comment out a resource block.
        [switch]$CommentOUT = $false,
        
        # This allows comments to be added to various code blocks.
        [string]$Comment,

        # This allows conditional resource blocks
        [Parameter(ParameterSetName = "Resource")]
        [scriptblock]$Condition,

        # This Output Path is for the Configuration Block, not this function.
        [Parameter(ParameterSetName = "InvokeConfiguration")]
        [string]$OutputPath = $(Join-Path -Path $PSScriptRoot -ChildPath "Output")
    )
    
    $DSCString = ""
    switch ($PSCmdlet.ParameterSetName)
    {
        "Configuration" 
        { 
            # Add comments if there are comments.
            if ($PSBoundParameters.ContainsKey("Comment"))
            {
                $Comment = "`n<#`n$Comment`n#>"
            }
            else
            {
                $Comment = ""
            }
            
            # Output the DSC String.
            $DSCString = @"
$Comment       
Configuration $Name`n{`n`n`t
"@ 
        }
        "ModuleImport"
        { 
            # Use this block to reset our Conflict Engine.
            $Script:GlobalConflictEngine = @{}
            $ModuleNotFound = @()
            # Loop through each module.
            foreach ($m in $ModuleName)
            {
                if (!(Get-command Get-DscResource -ErrorAction SilentlyContinue))
                {
                    Import-module PSDesiredStateConfiguration -Force
                }

                # Use Get-DSCResource to determine REQUIRED parameters to resource.
                $resources = Get-DscResource -Module $m -ErrorAction SilentlyContinue
                if ($resources -ne $null)
                {
                    # Loop through every resource in the module.
                    foreach ($r in $resources)
                    {
                        # Add a blank entry for the Resource Block with Required Parameters.
                        $Script:GlobalConflictEngine[$r.Name] = @()
                        $tmpHash = @{}
                        $r.Properties.Where( {$_.IsMandatory}) | ForEach-Object { $tmpHash[$_.Name] = ""}
                        $Script:GlobalConflictEngine[$r.Name] += $tmpHash

                        if ($r.Name -eq "Registry" -and $r.ModuleName -eq "PSDesiredStateConfiguration")
                        {
                            $script:ExclusiveFlagAvailable = $r.Properties.Name -contains 'Exclusive'
                        }
                    }
                }
                else
                {
                    Write-Warning "Write-DSCString: Module ($m) not found on System.  Please re-run conversion when module is available."
                    $ModuleNotFound += $m
                }
            }
            
            $ModuleName = $ModuleName | Where-Object {$_ -notin $ModuleNotFound}

            # Output our Import-Module string.
            foreach ($m in $ModuleName)
            {
                $DSCString += "Import-DSCResource -ModuleName '$m'`n`t" 
            }

            foreach ($m in $ModuleNotFound)
            {
                $DSCString += "# Module Not Found: Import-DSCResource -ModuleName '$m'`n`t" 
            }
        }
        "Node" { $DSCString = "Node $Name`n`t{`n" }
        "InvokeConfiguration" { $DSCString = "$Name -OutputPath '$($OutputPath)'" }
        "CloseNodeBlock" { $DSCString = "`t}" }
        "CloseConfigurationBlock" { $DSCString = "`n}`n" }          
        "Resource"
        {
            $Tabs = 2
            $DSCString = ""
			# A Condition was specified for this resource block.
			# Variables to be used for commeting out resource if necessary.
			$CommentStart = ""
			$CommentEnd = ""
			
			if ($CommentOut)
			{
				$CommentStart = "<#"
				$CommentEnd = "#>"
			}
			
			if ($PSBoundParameters.ContainsKey("Condition"))
			{
				if ($CommentOUT -eq $true)
				{
					$DSCString += "$(Get-Tabs $Tabs)$($CommentStart)if ($($Condition.ToString()))`n $(Get-Tabs $Tabs){`n"
				}
				else
				{
					$DSCString += "$(Get-Tabs $Tabs)if ($($Condition.ToString()))`n $(Get-Tabs $Tabs){`n"
				}
				$Tabs++
			}
			<#if ($PSBoundParameters.ContainsKey("Condition"))
            {
                $DSCString += "$(Get-Tabs $Tabs)if ($($Condition.ToString()))`n $(Get-Tabs $Tabs){`n"
                $Tabs++
            }#>

            # Variables to be used for commeting out resource if necessary.
            $CommentStart = ""
            $CommentEnd = ""
			
			$CommentOUT = Test-Conflicts -Type $Type -Name $Name -Resource $Parameters -CommentOut:$CommentOUT
            # If we are commenting this block out, then set up our comment characters.                        
            if ($CommentOut -and -not ($PSBoundParameters.ContainsKey("Condition")))
            {
                $CommentStart = "<#"
                $CommentEnd = "#>"
			}
			else
			{
				#Write-Host "if statement false"
				#Write-Host $CommentOUT
				#Write-Host $PSBoundParameters.ContainsKey("Condition")
			}
			
			# If they passed a comment FOR the block, add it above the block.
            if ($PSBoundParameters.ContainsKey("Comment"))
            {
                $tmpComment = "<#`n"
                # Changed from ForEach-Object { $tmpComment += "`t`t$_`n"}
                $tmpComment += $Comment -split "`n" | ForEach-Object { "$(Get-Tabs $Tabs)$_`n"}
                $tmpComment += "$(Get-Tabs $Tabs)#>`n$(Get-Tabs $Tabs)"
                $Comment = $tmpComment
            }
            else
            {
                $Comment = ""
            }

            # Start the Resource Block with Comment and CommentOut characters if necessary.
            $DSCString += "$(Get-Tabs $Tabs)$Comment$($CommentStart)$Type '$($Name)'`n$(Get-Tabs $Tabs){"
            $Tabs++
            foreach ($key in $Parameters.Keys)
            {
				try
				{
					$DSCString += Write-DSCStringKeyPair -Key $key -Value $Parameters[$key] -Tabs $Tabs -ErrorAction Stop
				}
				catch
				{
					Write-Warning "The command to Write-DSCStringKeyPair failed due to invalid data.  The returned error was $($Error[0])"
				}
			}
            $Tabs--
            $DSCString += "`n`n$(Get-Tabs $Tabs)}$CommentEnd`n"

            $Tabs--
            if ($PSBoundParameters.ContainsKey("Condition"))
			{
				$CommentStart = "<#"
				$CommentEnd = "#>"
				if ($CommentOUT -eq $true)
				{
					#Write-Host "Condition"
					$DSCString += "`n`n$(Get-Tabs $Tabs)}$($CommentEnd)"
				}
				else
				{
					#Write-Host "no condition"
					$DSCString += "`n`n$(Get-Tabs $Tabs)}"
				}
			}
			
			$DSCString += "`n`n"
        }
    }

    Write-Verbose $DSCString

    # Return our DSCstring.
    return $DSCString
}

function Get-IniContent
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory=$true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName=$true)]
        [System.String]$Path
    )

    $ini = @{}
    switch -regex -file $Path
    {
        "^\[(.+)\]"  # Section
        {
            $section = $matches[1]
            $ini[$section] = @{}
            $CommentCount = 0
        }
        "^(;.*)$"  # Comment
        {
            $value = $matches[1]
            $CommentCount = $CommentCount + 1
            $name = "Comment" + $CommentCount
            $ini[$section][$name] = $value.Trim()
            continue
        } 
        "(.+)\s*=(.*)"  # Key
        {
            $name,$value = $matches[1..2]
            $ini[$section][$name.Trim()] = $value.Trim()
            # Need to replace double quotes with `"
            continue
        }
        "\`"(.*)`",(.*)$" 
        { 
            $name, $value = $matches[1..2]
            $ini[$section][$name.Trim()] = $value.Trim()
            continue
        }
    }
    return $ini
}


Function Complete-Configuration
{
    [CmdletBinding()]
    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigString,

        [Parameter()]
        [string]$OutputPath = $(Join-Path -Path $pwd.path -ChildPath "Output")
    )
    
    if ($ConfigString -match "(?m)Configuration (?<Name>.*)$")
    {
        $CallingFunction = $Matches.Name
    }
    else
    {
        $CallingFunction = (Get-PSCallStack)[1].Command
    }

    if (!(Test-Path $OutputPath))
    {
        mkdir $OutputPath
    }
    
    $scriptblock = [scriptblock]::Create($ConfigString)
    
    if (!$?)
    {
        # Somehow CallingFunction, defined above, is not useable right here.  Not sure why
        $Path = $(Join-Path -Path $OutputPath -ChildPath "$($CallingFunction).ps1.error")
        $ConfigString > $Path
        
        Write-Error "Could not CREATE ScriptBlock from configuration. Creating PS1 Error File: $Path. Please rename error file to PS1 and open for further inspection. Errors are listed below"
        return $false
    }
    
    $output = Invoke-Command -ScriptBlock $scriptblock
    
    if (!$?)
    {
        $Path = $(Join-Path -Path $OutputPath -ChildPath "$($CallingFunction).ps1.error")
        $scriptblock.ToString() > $Path
        
        Write-Error "Could not COMPILE cofiguration. Storing ScriptBlock: $Path.  Please rename error file to PS1 and open for further inspection. Errors are listed below"
        foreach ($e in $output)
        {
            Write-Error $e
        }
        return $false
    }
        
    return $true
}

# Clear our processing history on each Configuration Creation.
Function Clear-ProcessingHistory
{
    $ProcessingHistory.Clear()
}

# Write out summary data and output proper files based on success/failure.
Function Write-ProcessingHistory
{
    [CmdletBinding()]
    [OutputType([String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [bool]$Pass,

        [Parameter()]
        [string]$OutputPath = $(Join-Path -Path $pwd.path -ChildPath "Output")
    )
    
    if (!(Test-Path $OutputPath))
    {
        mkdir $OutputPath | Out-Null
    }

    if (((Get-Module -ListAvailable).name -contains "Pester"))
    {
        Import-Module Pester
    }
    elseif (!((Get-Module).name -contains "Pester"))
    {
        Write-ProcessingHistory_NonPester -Pass $Pass 
        Write-ProcessingHistory_NonPester -Pass $Pass *> $(Join-Path -Path $OutputPath -ChildPath "Summary.log")
        return
    }
        
    New-Variable -Name successes -Option AllScope -Force
    New-Variable -Name disabled -Option AllScope -Force
    New-Variable -Name conflict -Option AllScope -Force
    New-Variable -Name resourcenotfound -Option AllScope -Force
    New-Variable -Name parsingerror -Option AllScope -Force
    $successes = $disabled = $conflict = $parsingerror = $resourcenotfound = 0
    $History = Get-Variable ProcessingHistory
    foreach($KeyPair in $History.Value.GetEnumerator())
    {
        $old_success = $successes
        $old_disabled = $disabled
        $old_conflict = $conflict
        $old_resourcenotfound = $resourcenotfound        
        $old_parsingerror = $parsingerror

        $Describe = "Parsing Summary: $((Get-PsCallStack)[1].Command) - $(@("FAILED", "SUCCEEDED")[[int]$Pass])`n`t$($KeyPair.Key.ToUpper()) Resources"        
        Describe $Describe {

            foreach ($Resource in $KeyPair.Value.Where({($_.Disabled -eq $false) -and ($_.Conflict -eq $false) -and ($_.ResourceNotFound -eq $false) -and ($_.ParsingError -eq $false)}))
            {
                It "Parsed: $($Resource.Name)" {
                    $Resource.Disabled | Should Be $false
                } 
                $successes++                         
            }

            foreach ($Resource in $KeyPair.Value.Where({$_.Disabled}))
            {
                It "Disabled: $($Resource.Name)" {
                    $Resource.Disabled | Should Be $true
                }          
                $disabled++
            }

            foreach ($Resource in $KeyPair.Value.Where({$_.Conflict}))
            {
                It "Found Conflicts: $($Resource.Name)" {
                    $Resource.Conflict | Should Be $true
                } -Pending    
                $conflict++
            }

            foreach ($Resource in $KeyPair.Value.Where({$_.ResourceNotFound}))
            {
                It "Had Missing Resources: $($Resource.Name)" {
                    $Resource.ResourceNotFound | Should Be $true
                } -Skip
                $resourcenotfound++
            } 

            foreach ($Resource in $KeyPair.Value.Where({$_.ParsingError}))
            {
                It "Had No Parsing Errors: $($Resource.Name)" {
                    $Resource.ParsingError | Should Be $false
                }          
                $parsingerror++
            }
        } *>> $(Join-Path -Path $OutputPath -ChildPath "Summary.log")

        $successes = $old_success
        $disabled = $old_disabled
        $conflict = $old_conflict
        $resourcenotfound = $old_resourcenotfound
        $parsingerror = $old_parsingerror

        Describe $Describe {

            foreach ($Resource in $KeyPair.Value.Where({($_.Disabled -eq $false) -and ($_.Conflict -eq $false) -and ($_.ResourceNotFound -eq $false) -and (($_.ParsingError -eq $false))}))
            {
                It "Parsed: $($Resource.Name)" {
                    $Resource.Disabled | Should Be $false
                } 
                $successes++                         
            }

            foreach ($Resource in $KeyPair.Value.Where({$_.Disabled}))
            {
                It "Disabled: $($Resource.Name)" {
                    $Resource.Disabled | Should Be $true
                } -Skip          
                $disabled++
            }

            foreach ($Resource in $KeyPair.Value.Where({$_.Conflict}))
            {
                It "Found Conflicts: $($Resource.Name)" {
                    $Resource.Conflict | Should Be $true
                } -Pending    
                $conflict++
            }

            foreach ($Resource in $KeyPair.Value.Where({$_.ResourceNotFound}))
            {
                It "Had Missing Resources: $($Resource.Name)" {
                    $Resource.ResourceNotFound | Should Be $true
                } -Skip
                $resourcenotfound++
            }

            foreach ($Resource in $KeyPair.Value.Where({$_.ParsingError}))
            {
                It "Had No Parsing Errors: $($Resource.Name)" {
                    $Resource.ParsingError | Should Be $false
                }          
                $parsingerror++
            }
        } 
    } 
    
    $tmpBlock = { 
        Write-Host "TOTALS" -ForegroundColor White 
        Write-Host "------" -ForegroundColor White
        Write-Host "SUCCESSES: $successes" -ForegroundColor Green
        Write-Host "DISABLED: $disabled" -ForegroundColor Gray
        Write-Host "MISSING RESOURCES: $resourcenotfound" -ForegroundColor Yellow
        Write-Host "CONFLICTS: $conflict" -ForegroundColor Cyan 
        Write-Host "PARSING ERROR: $resourcenotfound" -ForegroundColor Red
        Write-Host "______________________" -ForegroundColor White
        Write-Host "TOTAL: $($successes + $disabled + $conflict + $resourcenotfound + $parsingerror)" -ForegroundColor White
    }

    $tmpBlock.Invoke() *>> $(Join-Path -Path $OutputPath -ChildPath "Summary.log")
    $tmpBlock.Invoke()
}

Function Write-ProcessingHistory_NonPester
{
    [CmdletBinding()]
    [OutputType([String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [bool]$Pass
    )
        
    Write-Host "Parsing Summary: $((Get-PsCallStack)[1].Command) - $(@("FAILED", "SUCCEEDED")[[int]$Pass])" -ForegroundColor @("RED", "GREEN")[[int]$Pass]
    Write-Host "---------------" -ForegroundColor White
    $History = Get-Variable ProcessingHistory
    $successes = $disabled = $conflict = $resourcenotfound = $parsingerror = 0
    foreach ($KeyPair in $History.Value.GetEnumerator())
    {
        foreach ($Resource in $KeyPair.Value.Where( {($_.Disabled -eq $false) -and ($_.Conflict -eq $false)}))
        {
            Write-Host "Parsed: $($Resource.Name)" -ForegroundColor Green
            $successes++
        }

        foreach ($Resource in $KeyPair.Value.Where( {$_.Disabled}))
        {
            Write-Host "Disabled: $($Resource.Name)" -ForegroundColor Gray
            $disabled++          
        }

        foreach ($Resource in $KeyPair.Value.Where( {$_.Conflict}))
        {
            Write-Host "Found Conflicts: $($Resource.Name)" -ForegroundColor Cyan
            $conflict++      
        }

        foreach ($Resource in $KeyPair.Value.Where( {$_.ResourceNotFound}))
        {
            Write-Host "Missing Resources: $($Resource.Name)" -ForegroundColor Yellow
            $resourcenotfound++      
        }

        foreach ($Resource in $KeyPair.Value.Where( {$_.ParsingError}))
        {
            Write-Host "Parsing Error: $($Resource.Name)" -ForegroundColor Red
            $parsingerror++      
        }
    }

    Write-Host "TOTALS" -ForegroundColor White
    Write-Host "------" -ForegroundColor White
    Write-Host "SUCCESSES: $successes" -ForegroundColor Green
    Write-Host "DISABLED: $disabled" -ForegroundColor Gray
    Write-Host "MISSING RESOURCES: $resourcenotfound" -ForegroundColor Yellow
    Write-Host "CONFLICTS: $conflict" -ForegroundColor Cyan 
    Write-Host "PARSING ERROR: $resourcenotfound" -ForegroundColor Red
    Write-Host "______________________" -ForegroundColor White
    Write-Host "TOTAL: $($successes + $disabled + $conflict + $resourcenotfound + $parsingerror)" -ForegroundColor White
}
#endregion
#region XML Helpers
Function Get-NodeComments
{
    [CmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.XML.XmlElement]$Node
    )

    # Grab all of the comments.
    $Setting = "../.."
    $ProductInfo = $node.SelectNodes($Setting).Content.ProductInfo
    $Comments = $ProductInfo | Out-String
    $Comments = $Comments -replace ": ProductRef", ": $($ProductInfo.ProductRef.product_ref)"
    $Comments = ($Comments -replace "ManualTestProcedure :", "") -replace "ValueRange          : ValueRange", ""
    $Comments = $Comments -replace ": CCEID-50", ": $($ProductInfo.'CCEID-50'.ID)"
    $Comments = $Comments.Trim()
    <# This is how to get string data into object format.
        (((($Comments -replace ": ", "= '") -replace "(`n)([A-Z])", ("'`$1" + '$2')) + '"') -replace "`n[^A-Z]", "") -replace "\\", "\\" | ConvertFrom-StringData
    #>

    return $Comments
}

# Reverse function to get StringData Object from Comments String output of Get-NodeComments.
Function Get-NodeDataFromComments
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [String]$Comments
    )

    Try 
    {
        $comments = $comments -replace "[^\u0000-\u007F]", ""
        $comments = ((((($Comments -replace "(?m)^([^ ]*)\s*:\s?", "`$1 = '") -replace "(?m)^[^A-Z]*`$`n", "") -replace "(?m)`$(`n)([A-Z])", ("'`$1" + '$2')) + '"')) -replace "\\", "\\"
        $tmpComments = $Comments -split "'`n"
        $Comments = ($tmpComments | ForEach-Object{ (($_ -replace "`n", "") + "'") -replace "'", "" }) -join "`n"
        $object = $comments | ConvertFrom-StringData
    }
    Catch
    {
        Write-Error "Cannot convert COMMENT Data"
    }

    return $object
}
#endregion