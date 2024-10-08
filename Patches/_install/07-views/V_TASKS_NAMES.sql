/****** Object:  View [V_TASKS_NAMES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[V_TASKS_NAMES]'))
EXEC dbo.sp_executesql @statement = N'
create view [V_TASKS_NAMES]
as

select 	
	t.PARENT_ID,
	t.TASK_ID,
	t.TITLE,
	t.AUTHOR_ID,
	t.ANALYZER_ID,
	AUTHOR_NAME = m1.NAME,
	ANALYZER_NAME = m2.NAME,
	t.EXECUTOR_NAME,
	t.STATUS_ID,
	STATUS_NAME = s.NAME,
	s.CSS_CLASS as STATUS_CSS,
	IS_OVERDUE = cast(
		case
			when t.status_id <> 5 and t.d_deadline < cast(getdate() as date) then 1
			else 0
		end as bit)
from tasks t
	inner join mols m1 on m1.mol_id = t.author_id
	inner join mols m2 on m2.mol_id = t.analyzer_id
	inner join tasks_statuses s on s.status_id = t.status_id' 
GO
