/****** Object:  View [BUDGETS_NAMES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[BUDGETS_NAMES]'))
EXEC dbo.sp_executesql @statement = N'
CREATE VIEW [BUDGETS_NAMES] AS
	SELECT BUDGET_ID, NAME FROM DBO.BUDGETS
' 
GO
