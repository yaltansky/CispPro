
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[AGENTS_CONTACTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [AGENTS_CONTACTS](
	[SUBJECT_ID] [int] NOT NULL DEFAULT ((-2)),
	[AGENT_ID] [int] NOT NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](255) NULL,
	[SURNAME] [varchar](50) NULL,
	[NAME1] [varchar](50) NULL,
	[NAME2] [varchar](50) NULL,
	[POST_NAME] [varchar](50) NULL,
	[POST_RESPONSIBLES] [varchar](512) NULL,
	[PHONE] [varchar](50) NULL,
	[PHONE_MOBILE] [varchar](20) NULL,
	[EMAIL] [varchar](50) NULL,
	[BIRTHDAY] [smalldatetime] NULL,
	[IS_MAN] [bit] NOT NULL DEFAULT ((1)),
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[ACCOUNT_LEVEL_ID] [int] NULL,
	[STATUS_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

