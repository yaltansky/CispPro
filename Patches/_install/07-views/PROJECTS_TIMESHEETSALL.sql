﻿IF OBJECT_ID('PROJECTS_TIMESHEETSALL') IS NOT NULL DROP VIEW PROJECTS_TIMESHEETSALL
GO
CREATE VIEW PROJECTS_TIMESHEETSALL AS
SELECT
    X.TIMESHEET_ID,
    X.PROJECT_ID,
    PROJECT_NAME = P.NAME,
    X.TASK_ID,
    TASK_NAME = X.NAME,
	X.D_DEADLINE,
    X.MOL_ID,
    MOL_NAME = MOLS.NAME,
    X.SUM_PLAN_H,
    X.SUM_FACT_H
FROM PROJECTS_TIMESHEETS X
	JOIN PROJECTS P ON P.PROJECT_ID = X.PROJECT_ID
	JOIN MOLS ON MOLS.MOL_ID = X.MOL_ID
WHERE ISNULL(X.IS_CLOSED,0) = 0

GO
