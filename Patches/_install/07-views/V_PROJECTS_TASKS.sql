/****** Object:  View [V_PROJECTS_TASKS]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[V_PROJECTS_TASKS]'))
EXEC dbo.sp_executesql @statement = N'
CREATE VIEW [V_PROJECTS_TASKS]
AS

SELECT
	PROJECT_ID,
	PARENT_ID,
	TASK_ID,
	TASK_NUMBER,
	NAME,
	DURATION,
	PROGRESS,
	D_AFTER,
	D_BEFORE,
	PREDECESSORS,
	HAS_CHILDS,
	IS_CRITICAL,
	IS_LONG,
	COUNT_CHECKS,
	COUNT_CHECKS_ALL
from projects_tasks
where status_id <> -1
' 
GO
