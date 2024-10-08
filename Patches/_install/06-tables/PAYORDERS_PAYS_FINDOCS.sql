/****** Object:  Table [PAYORDERS_PAYS_FINDOCS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PAYORDERS_PAYS_FINDOCS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PAYORDERS_PAYS_FINDOCS](
	[FINDOC_ID] [int] NOT NULL,
	[ACCOUNT_ID] [int] NULL,
	[STATUS_ID] [int] NULL,
	[D_DOC] [datetime] NULL,
	[NUMBER] [varchar](50) NULL,
	[AGENT_ID] [int] NULL,
	[AGENT_NAME] [varchar](100) NULL,
	[AGENT_ACC] [varchar](50) NULL,
	[AGENT_INN] [varchar](30) NULL,
	[DOGOVOR_ID] [int] NULL,
	[SUBJECT_ID] [int] NULL,
	[SUBJECT_NAME] [varchar](150) NULL,
	[BUDGET_ID] [int] NULL,
	[ARTICLE_ID] [int] NULL,
	[CCY_ID] [char](3) NULL,
	[VALUE_CCY] [decimal](18, 2) NOT NULL,
	[VALUE_RUR] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[UNIQUE_ID] [varbinary](32) NULL,
	[HAS_DETAILS] [bit] NULL,
	[HAS_TAGS] [bit] NULL,
	[CONTENT] [varchar](max) NULL,
	[TALK_ID] [int] NULL,
	[WBS_BOUND] [bit] NOT NULL,
	[SUBJECT_SHORT_NAME] [varchar](12) NULL,
	[ACCOUNT_NAME] [varchar](50) NULL,
	[EXTERN_ID] [int] NULL,
	[DETAIL_ID] [int] NULL
)
END
GO

