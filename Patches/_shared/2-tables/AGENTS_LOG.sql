
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[AGENTS_LOG]') AND type in (N'U'))
BEGIN
CREATE TABLE [AGENTS_LOG](
	[TRAN_ID] [uniqueidentifier] NULL,
	[TRAN_CALLER] [varchar](max) NULL,
	[TRAN_ACTION] [char](1) NULL,
	[TRAN_USER_ID] [int] NULL,
	[AGENT_ID] [int] NULL,
	[NAME] [varchar](255) NULL,
	[INN] [varchar](30) NULL,
	[TRAN_DATE] [datetime] NULL DEFAULT (getdate())
)
END
GO

