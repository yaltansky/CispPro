/****** Object:  View [PROJECTS_TREES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[PROJECTS_TREES]'))
EXEC dbo.sp_executesql @statement = N'
CREATE VIEW [PROJECTS_TREES] AS SELECT * FROM TREES WHERE TYPE_ID = 1
' 
GO
