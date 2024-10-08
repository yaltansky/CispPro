/****** Object:  View [PROJECTS_TASKS_BASE]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[PROJECTS_TASKS_BASE]'))
EXEC dbo.sp_executesql @statement = N'CREATE view [PROJECTS_TASKS_BASE]
as

select 
    PROJECT_ID,
    TASK_ID,
    TASK_NUMBER,
    NAME,
    D_FROM,
    D_TO,
    D_AFTER,
    D_BEFORE,
    DURATION,
    PROGRESS,
    IS_CRITICAL,
    IS_LONG,
    IS_OVERLONG,
    EXECUTE_LEVEL,
    DURATION_BUFFER,
	PREDECESSORS
from projects_tasks
' 
GO
