/****** Object:  View [PA_BRANCHES_REF]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[PA_BRANCHES_REF]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [PA_BRANCHES_REF] AS SELECT BRANCH_ID, NAME FROM PA_BRANCHES
' 
GO
