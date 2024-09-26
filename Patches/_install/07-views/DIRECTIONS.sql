/****** Object:  View [DIRECTIONS]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[DIRECTIONS]'))
EXEC dbo.sp_executesql @statement = N'
CREATE VIEW [DIRECTIONS]
AS 
SELECT 
	DEPT_ID AS DIRECTION_ID, 
	ISNULL(SHORT_NAME, NAME) AS NAME,
	CHIEF_ID
FROM depts

' 
GO
