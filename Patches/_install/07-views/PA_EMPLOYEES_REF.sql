/****** Object:  View [PA_EMPLOYEES_REF]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[PA_EMPLOYEES_REF]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [PA_EMPLOYEES_REF] AS 
	SELECT EMPLOYEE_ID, NAME
	FROM PA_EMPLOYEES
' 
GO
