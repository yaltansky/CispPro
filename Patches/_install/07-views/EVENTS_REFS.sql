/****** Object:  View [EVENTS_REFS]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[EVENTS_REFS]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [EVENTS_REFS] AS SELECT EVENT_ID, NAME FROM EVENTS
' 
GO
