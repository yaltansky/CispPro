/****** Object:  View [SDOCS_MFR_SOURCES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_SOURCES]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [SDOCS_MFR_SOURCES] AS
SELECT cast(ID as int) as SOURCE_ID, NAME FROM OPTIONS_LISTS
WHERE L_GROUP = ''MfrSdocsSources''' 
GO
