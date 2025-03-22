
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FINDOCS_UPLOADS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FINDOCS_UPLOADS](
	[GROUP_ID] [uniqueidentifier] NULL,
	[UPLOAD_ID] [int] IDENTITY(1,1) NOT NULL,
	[FILE_NAME] [varchar](1024) NULL,
	[FILE_URL] [varchar](1024) NULL,
	[DATA] [xml] NULL,
	[SUBJECT_ID] [int] NULL,
	[ACCOUNT_ID] [int] NULL,
	[CHECK_SALDO] [bit] NULL DEFAULT ((1)),
	[ERRORS] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[MOL_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[UPLOAD_ID] ASC
)
)
END
GO

