/****** Object:  View [PA_DEPTS_REF]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[PA_DEPTS_REF]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [PA_DEPTS_REF] AS SELECT DEPT_ID, NAME FROM DEPTS
' 
GO
