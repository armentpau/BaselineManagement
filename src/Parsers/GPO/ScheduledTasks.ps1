#region GPO Parsers
#need to redo convert-torepetitionstring to do [system.datetime]'00:00:00'
Function Convert-ToRepetitionString
{
    [OutputType([string])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [int]$minutes
    )

    $timeSpan = New-Object System.TimeSpan -ArgumentList 0, 0, 0, $minutes
    $interval = "P"
    if ($timeSpan.Days -gt 0)
    {
        $interval += "DT" + $timeSpan.Days
    }
    if ($timeSpan.Hours -gt 0)
    {
        $interval += "H" + $timeSpan.Hours
    }

    if ($timeSpan.Minutes -gt 0)
    {
        $interval += "M" + $timeSpan.Minutes
    }

    if ($timeSpan.Seconds -gt 0)
    {
        $interval += "S" + $timeSpan.Seconds
    }
}

Function Test-BoolOrNull
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        $Value
    )

    if ($Value -ne $Null)
    {
        return [bool]$Value
    }
    else
    {
        return $null
    }
}

Function Remove-EmptyValues
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        $hashtable
    )
    $keys = $hashtable.keys.Clone()
    foreach ($key in $keys)
    {
            if ($hashtable[$key] -is [System.Collections.Hashtable])
            {
                Remove-EmptyValues -hashtable $hashtable[$key]
                if ($hashtable[$key].Keys.Where({$_ -ne "EmbeddedInstance"}).Count -eq 0)
                {
                    $hashtable.Remove($key)
                }
            }
            elseif ($hashtable[$key] -is [System.Array])
            {
                $goodEntries = @()
                for ($i = 0; $i -lt $hashtable[$key].Count; $i++)
                {
                    if ($hashtable[$key][$i] -is [System.Collections.Hashtable])
                    {
                        Remove-EmptyValues -hashtable $hashtable[$key][$i]
                        if ($hashtable[$key][$i].Keys.Where({$_ -ne "EmbeddedInstance"}).count -gt 0)
                        {
                            $goodEntries += $i
                        }
                    }
                    else 
                    {
                        $goodEntries += $i
                    }
                }

                $hashtable[$key] = $hashtable[$key][$goodEntries]
            }
            else
            {
                if ($hashtable[$key] -eq $null)
                {
                    $hashtable.Remove($key)
                }
            }
    }
}

Function Write-GPOScheduledTasksXMLData
{
    [CmdletBinding()]
    [OutputType([String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$XML    
    )

    $schTaskHash = @{}
    $Properties = $XML.Properties
    # Set up Task Triggers if necessary
    switch -regex ($XML.LocalName)
	{
		"^(Task|ImmediateTask)$"
		{
			$schTaskHash.TaskName = $Properties.Name
			$schTaskHash.TaskPath = "\DSC\"
			$schTaskHash.ActionExecutable		      = $Properties.appName
			$schTaskHash.ActionWOrkingPath  = $Properties.startIn
			$schTaskHash.ActionArguments		  = $Properties.args
			if ($Properties.runAs)
			{
					$schTaskHash.executeascredential	= $Properties.runAs
					#RunLevel		  = @("Highest", "Limited")[$Properties.systemRequired]
			}
		
			$schTaskHash.Enable					    = Test-BoolOrNull $Properties.enabled
			$schTaskHash.RunOnlyIfIdle = Test-BoolOrNull $Properties.startOnlyIfIdle
			$schTaskHash.ExecutionTimeLimit		    = (Convert-ToRepetitionString -minutes $Properties.maxRunTime)
			$schTaskHash.DontStopOnIdleEnd			= -not (Test-BoolOrNull $Properties.stopOnIdleEnd)
			$schTaskHash.DontStopIfGoingOnBatteries	= -not (Test-BoolOrNull $Properties.stopIfGoingOnBatteries)
			$schTaskHash.AllowStartIfOnBatteries  	= -not (Test-BoolOrNull $Properties.noStartIfOnBatteries)
			
			if ($_ -eq "ImmediateTask")
			{
				$schTaskHash.starttime	  = "`"$(get-date(Get-Date).AddMinutes(15) -f 'HH:mm')`""
				break
			}
			
			$triggers = @()
			
			foreach ($t in $Properties.Triggers.ChildNodes)
			{
				$tmpHash = @{ }
				switch ($t.Type)
				{
					'IDLE'
					{
						
					}
					'ONCE'
					{
						
					}
					'STARTUP'
					{
						
					}
					'LOGON'
					{
						
					}
					'DAILY'
					{
						if ($t.Interval)
						{
							$tmpHash.DaysInterval = $t.interval
						}
					}
					'WEEKLY'
					{
						if ($t.Interval)
						{
							$tmpHash.WeeksInterval = $t.interval
						}
						
						if ($t.week)
						{
							# MUST be FIRST, SECOND, THIRD, FOURTH, or LAST to indicate the week position in the month when the task executes.
							Write-Warning "Write-GPOScheduledTaskXMLData: Week of Month interval is not supported in DSC Resource"
						}
					}
					'MONTHLY'
					{
						if ($t.months)
						{
							# BIT MASK: MUST map to the month in which a job will process. The field is a 12-bit mask with 1 assigned to January, 2 to February, 4 to March, 8 to April, 16 to May, 32 to June, 64 to July, 128 to August, 256 to September, 512 to October, 1024 to November, and 2048 to December.
							Write-Warning "Write-GPOScheduledTaskXMLData: MONTHS interval is not supported in DSC Resource"
						}
					}
				}
				
				#if ($t.hasEndDate)
				#{
					#$tmpHash.EndBoundary = "`"$(Get-Date -Day $t.endDay -Month $t.endMonth -Year $t.endYear)`""
				#}
				
				$tmpHash.DaysOfWeek = 0 # MUST map to the day of the week in which the job will process for jobs that execute on a selected day. The field is a bit mask with 1 assigned to Sunday, 2 to Monday, 4 to Tuesday, 8 to Wednesday, 16 to Thursday, 32 to Friday, and 64 to Saturday.
			
				$tmpHash.StartTime = "`"$(Get-Date -Year $t.beginYear -Month $t.beginMonth -Day $t.beginDay -Hour $t.startHour -Minute $t.startMinutes -f 'HH:mm')`""
				
				if ($t.repeatTask)
				{
					$duration = Convert-ToRepetitionString -minutes $t.minutesDuration
					$interval = Convert-ToRepetitionString -minutes $t.minutesInterval	
					$schTaskHash.RepeatInterval		   = $interval
					$schTaskHash.RepetitionDuration		   = $duration
				}
				
				#$tmpHash.EmbeddedInstance = "TaskTriggers"
				#$tmpHash.Enabled = $True
				#$tmpHash.Id = "$($t.Type) Trigger($($schTaskHash.TaskName)): $(New-Guid)"
				#$triggers += $tmpHash
			}
			
			
		}
		
		"^(Task|ImmediateTask)V2$"
		{
			$schTaskHash.TaskName = $XML.Name
			$schTaskHash.TaskPath = "\DSC\"
			
			#$schTaskHash.TaskAction = @()
			foreach ($a in $Properties.Task.Actions.ChildNodes)
			{
				if ($a.LocalName -eq "Exec")
				{
					$schTaskHash.ActionExecutable		      = $a.Command
					$schTaskHash.ActionWorkingPath  = $a.WorkingDirectory
					$schTaskHash.ActionArguments		  = $a.Arguments
				}
			}
			
			if ($Properties.Task.Principals.Count -gt 0)
			{
				foreach ($p in $Properties.Task.Prinicpals.ChildNodes)
				{
					$schTaskHash.executeAsCredential = $p.UserId
					break
				}
			}
			elseif ($Properties.runAs)
			{
					$schTaskHash.executeAsCredential	      = $Properties.runAs
					#LogonType		  = $Properties.logonType
				
				
				<#if ($Properties.systemRequired)
				{
					$principal.RunLevel = @("Highest", "Limited")[$Properties.systemRequired]
				}
				#>
			}
			
				$schTaskHash.MultipleInstances		    = $Properties.Task.Settings.MultipleInstancePolicy
				$schTaskHash.Enable				    = Test-BoolOrNull $Properties.Task.Settings.enabled
				$schTaskHash.RunOnlyIfIdle				= Test-BoolOrNull $Properties.Task.Settings.runOnlyIfIdle
				$schTaskHash.ExecutionTimeLimit		    = $Properties.Task.Settings.executionTimeLimit
				$schTaskHash.Priority				    = $Properties.Task.Settings.Priority
				$schTaskHash.WakeToRun				    = Test-BoolOrNull $Properties.Task.Settings.WakeToRun
				$schTaskHash.Hidden					    = Test-BoolOrNull $Properties.Task.Settings.Hidden
				$schTaskHash.DisAllowDemandStart		    = -not (Test-BoolOrNull $Properties.Task.Settings.AllowStartOnDemand)
				$schTaskHash.disAllowHardTerminate		    = -not (Test-BoolOrNull $Properties.Task.Settings.AllowHardTerminate)
				$schTaskHash.StartWhenAvailable		    = Test-BoolOrNull $Properties.Task.Settings.StartWhenAvailable
				$schTaskHash.RunOnlyIfNetworkAvailable   = Test-BoolOrNull $Properties.Task.Settings.RunOnlyIfNetworkAvailable
				$schTaskHash.dontStopOnIdleEnd	  = -not (Test-BoolOrNull $Properties.Task.Settings.IdleSettings.StopOnIdleEnd)
				$schTaskHash.IdleDuration	  = $Properties.Task.Settings.IdleSettings.Duration
				$schTaskHash.idleWaitTimeOut	      = $Properties.Task.Settings.IdleSettings.WaitTimeOut
				$schTaskHash.RestartOnIdle	  = Test-BoolOrNull $Properties.Task.Settings.IdleSettings.RestartOnIdle
				$schTaskHash.RestartCount			    = $Properties.Task.Settings.RestartOnFailure.Count
				$schTaskHash.RestartInterval			    = $Properties.Task.Settings.RestartOnFailure.Interval
				$schtaskhash.dontStopIfGoingOnBatteries	    = -not (Test-BoolOrNull $Properties.Task.Settings.stopIfGoingOnBatteries)
				$schTaskHash.allowStartIfOnBatteries  = -not (Test-BoolOrNull $Properties.Task.Settings.DisallowStartIfOnBatteries)
			
			if ($_ -eq "ImmediateTaskV2")
			{
				$schTaskHash.starttime = "`"$(get-date(Get-Date).AddMinutes(15) -f 'HH:mm')`""
                break
            }

            $triggers = @()
					foreach ($t in $Properties.Task.Triggers.ChildNodes)
					{
						$tmpHash = @{ }
						switch -regex ($t.Name)
						{
							"(BootTrigger|EventTrigger|IdleTrigger|RegistrationTrigger|SessionStateChangeTrigger)"
							{
								Write-Warning "Write-GPOScheduledTaskXMLData: $_ Trigger type is not yet suppported."
								break
							}
							
							"LogonTrigger"
							{
								$tmpHash.User = $t.UserId
							}
							
							"CalendarTrigger"
							{
								switch ($t.ChildNodes.Name)
								{
									"ScheduleByDay"
									{
										$tmpHash.DaysInterval = $t.ScheduleByDay.DaysInterval
									}
									
									"ScheduleByWeek"
									{
										$tmpHash.WeeksInterval = $t.ScheduleByWeek.WeeksInterval
									}
									
									"StartBoundary"
									{
										$tmpHash.starttime = "`"$(get-date(Get-Date).AddMinutes(15) -f 'HH:mm')`""
										#$tmpHash.StartBoundary = "`"$($t.StartBoundary)`""
									}
									
									"Enabled"
									{
										$tmpHash.Enable = Test-BoolOrNull $t.Enabled
									}
									
									Default
									{
										Write-Warning "Write-GPOScheduledTaskXMLData:$_ Trigger Type is not supported."
									}
								}
							}
							
							".*"
							{
								$schTaskHash.Enable = Test-BoolOrNull $t.Enabled
								$schTaskHash.Starttime = "`"$($t.StartBoundary)`""
								#$tmpHash.EndBoundary = "`"$t.EndBoundary`""
								$schTaskHash.RandomDelay = $t.Delay
								#$tmpHash.ExecutionTimeLimit = $t.ExecutionTimeLimit
								#$tmpHash.TaskRepetition = @{
									#EmbeddedInstance   = "TaskRepetition"
									$schTaskHash.RepeatInterval		   = $t.Repetition.Interval
									$schtask.RepetitionDuration		   = $t.Repetition.Interval
									#StopAtDurationEnd  = Test-BoolOrNull $t.Repetition.StopAtDurationEnd
								
								#$tmpHash.EmbeddedInstance = "TaskTriggers"
							}
						}
						
						#$triggers += $tmpHash
					}
					
					#$schTaskHash.TaskTriggers = $triggers
				}
				
				Default
				{
					Write-Warning "Write-GPOScheduledTaskXMLData:$_ task type is not implemented"
				}
			}
			
			Remove-EmptyValues -hashtable $schTaskHash
			Write-DSCString -Resource -Type xScheduledTask -Name "ScheduledTask(XML): $($schTaskHash.TaskName)" -Parameters $schTaskHash
		}
#endregion