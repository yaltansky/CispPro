/****** Object:  View [DEALS_MAP_INSTANTS_BACK]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[DEALS_MAP_INSTANTS_BACK]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [DEALS_MAP_INSTANTS_BACK]
as
SELECT MA.INSTANT_ID, MA.INSTANT_NAME, MAM.TASK_NAME
from deals_map_instants ma
	join (
		select task_name, min(instant_id) as instant_id
		from deals_map_instants ma
		group by task_name
	) mam on mam.instant_id = ma.instant_id' 
GO
