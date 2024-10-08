/****** Object:  Table [APP_REGISTRY]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[APP_REGISTRY]') AND type in (N'U'))
BEGIN
CREATE TABLE [APP_REGISTRY](
	[REGISTRY_ID] [varchar](64) NULL,
	[VAL_STRING] [varchar](max) NULL,
	[VAL_NUMBER] [float] NULL,
	[VAL_DATE] [datetime] NULL,
	[NAME] [nvarchar](250) NULL,
	[VAL_TYPE] [varchar](20) NULL DEFAULT ('string'),
	[VAL_PARAM] [varchar](250) NULL,
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PARENT_ID] [int] NULL,
	[HAS_CHILDS] [bit] NULL,
	[NODE] [hierarchyid] NULL,
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[NOTE] [nvarchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_SHARED] [bit] NULL,
 CONSTRAINT [PK_APP_REGISTRY_ID] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

