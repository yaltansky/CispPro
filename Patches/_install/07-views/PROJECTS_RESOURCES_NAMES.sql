/****** Object:  View [PROJECTS_RESOURCES_NAMES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[PROJECTS_RESOURCES_NAMES]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [PROJECTS_RESOURCES_NAMES] as select RESOURCE_ID, NAME from PROJECTS_RESOURCES
' 
GO
