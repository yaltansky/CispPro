/****** Object:  View [UsersLogsView]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[UsersLogsView]'))
EXEC dbo.sp_executesql @statement = N'create view [UsersLogsView]
as
select 
	UserName = mols.name,
	u.UserId,
	u.url,
	u.TimeStart,
	u.TimeEnd,
	u.Request,
	cast(datediff(MS, TimeStart, TimeEnd)/1000. as decimal(10,2)) as TimeSpan
from UsersLogs u
	join mols on mols.mol_id = u.UserId
' 
GO
