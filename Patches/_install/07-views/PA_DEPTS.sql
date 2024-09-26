/****** Object:  View [PA_DEPTS]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[PA_DEPTS]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [PA_DEPTS] AS
SELECT  DEPT_ID, PARENT_ID, SUBJECT_ID, NAME, HAS_CHILDS, LEVEL_ID, SORT_ID, IS_DELETED FROM DEPTS
' 
GO
