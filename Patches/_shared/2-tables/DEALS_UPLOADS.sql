
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS_UPLOADS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS_UPLOADS](
	[GROUP_ID] [uniqueidentifier] NULL,
	[UPLOAD_ID] [int] IDENTITY(1,1) NOT NULL,
	[FILE_NAME] [varchar](1024) NULL,
	[DATA] [xml] NULL,
	[DEAL_ID] [int] NULL,
	[ERRORS] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[MOL_ID] [int] NULL,
	[FILE_DATA] [varbinary](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[UPLOAD_ID] ASC
)
)
END
GO

