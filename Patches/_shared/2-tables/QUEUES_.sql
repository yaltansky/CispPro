USE CISP_SHARED
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[QUEUES]') AND type in (N'U'))
BEGIN
CREATE TABLE [QUEUES](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PARENT_ID] [int] NULL,
	[QUEUE_ID] [uniqueidentifier] NOT NULL,
	[DBNAME] [varchar](32) NULL,
	[THREAD_ID] [varchar](32) NULL,
	[PRIORITY_ID] [int] NULL DEFAULT ((500)),
	[GROUP_NAME] [varchar](100) NULL,
	[MOL_ID] [int] NULL,
	[NAME] [varchar](100) NULL,
	[SQL_CMD] [nvarchar](max) NULL,
	[NOTE] [varchar](max) NULL,
	[ERRORS] [varchar](max) NULL,
	[ADD_DATE] [datetime] NULL DEFAULT (getdate()),
	[PROCESS_START] [datetime] NULL,
	[PROCESS_PROGRESS] [float] NULL,
	[PROCESS_END] [datetime] NULL,
	[CANCEL_DATE] [datetime] NULL,
	[PROCESS_DURATION]  AS (datediff(millisecond,[PROCESS_START],[PROCESS_END])),
	[TRY_COUNT] [int] NULL,
	[USE_RMQ] [bit] NULL,
PRIMARY KEY CLUSTERED 
(
	[QUEUE_ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[QUEUES]') AND name = N'IX_THREAD')
CREATE NONCLUSTERED INDEX [IX_THREAD] ON [QUEUES]
(
	[THREAD_ID] ASC
)
GO
