       
Configuration DSCFromGPO
{

	Import-DSCResource -ModuleName 'PSDesiredStateConfiguration'
	Import-DSCResource -ModuleName 'AuditPolicyDSC'
	Import-DSCResource -ModuleName 'SecurityPolicyDSC'
	Import-DSCResource -ModuleName 'BaselineManagement'
	Import-DSCResource -ModuleName 'xSMBShare'
	Import-DSCResource -ModuleName 'DSCR_PowerPlan'
	Import-DSCResource -ModuleName 'xScheduledTask'
	Import-DSCResource -ModuleName 'Carbon'
	# Module Not Found: Import-DSCResource -ModuleName 'PrinterManagement'
	# Module Not Found: Import-DSCResource -ModuleName 'rsInternationalSettings'
	Node localhost
	{
	}
}
DSCFromGPO -OutputPath 'C:\Users\949237\Documents\Repos\BaselineManagement\src\Output'
