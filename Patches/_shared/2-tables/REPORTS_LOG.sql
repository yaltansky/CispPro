
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[REPORTS_LOG]') AND type in (N'U'))
BEGIN
CREATE TABLE [REPORTS_LOG](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DBNAME] [varchar](30) NULL,
	[TEMPLATE_NAME] [varchar](150) NULL,
	[SQL_CMD] [varchar](max) NULL,
	[SQL_PARAMS] [varchar](max) NULL,
	[MOL_ID] [int] NULL,
	[PROCESS_START] [datetime] NULL,
	[PROCESS_END] [datetime] NULL,
	[PROCESS_DURATION]  AS (datediff(millisecond,[PROCESS_START],[PROCESS_END])),
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

