/****** Object:  View [TREES_NAMES]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[TREES_NAMES]'))
EXEC dbo.sp_executesql @statement = N'CREATE VIEW [TREES_NAMES] as select TREE_ID, NAME from TREES
' 
GO
