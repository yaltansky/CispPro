/****** Object:  View [SUBJECTS_REF]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[SUBJECTS_REF]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [SUBJECTS_REF] AS SELECT SUBJECT_ID, NAME, SHORT_NAME FROM SUBJECTS
' 
GO
