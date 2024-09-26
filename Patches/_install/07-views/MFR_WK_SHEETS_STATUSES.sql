/****** Object:  View [MFR_WK_SHEETS_STATUSES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[MFR_WK_SHEETS_STATUSES]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [MFR_WK_SHEETS_STATUSES] AS
SELECT cast(ID as int) as STATUS_ID, NAME FROM OPTIONS_LISTS
WHERE L_GROUP = ''MfrWkSheetsStatuses''' 
GO
