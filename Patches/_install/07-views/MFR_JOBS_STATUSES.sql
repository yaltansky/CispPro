/****** Object:  View [MFR_JOBS_STATUSES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[MFR_JOBS_STATUSES]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [MFR_JOBS_STATUSES] AS
	SELECT CAST(ID AS INT) AS STATUS_ID, NAME FROM OPTIONS_LISTS
	WHERE L_GROUP = ''MfrPlanJobStatuses''	
' 
GO
