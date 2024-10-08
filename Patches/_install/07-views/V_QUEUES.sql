/****** Object:  View [V_QUEUES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[V_QUEUES]'))
EXEC dbo.sp_executesql @statement = N'-- EXEC V_QUEUES ''CISP_SEZ'', @SEARCH = ''RUNNING''
CREATE VIEW [V_QUEUES]
AS

select x.*, 
	LAG_START = 
		case 
			when process_start is not null then datediff(second, x.add_date, x.process_start)
		end,
	MOL_NAME = mols.name,
	STATE = 
		case 
			when errors is not null then ''error''
			when process_start is not null and process_end is null then ''running''
			when process_start is null and process_end is null then ''running-wait''
			when process_duration > 0 then ''completed''
			else ''undefined''
		end
from queues x with(nolock)
	join mols on mols.mol_id = x.mol_id
where x.group_name not in (
	''broker-agent'',
	''broker-agent-low'',
	''queue-agent'',
	''jobs-queue-agent'',
	''jobs-details-agent''
	)' 
GO
