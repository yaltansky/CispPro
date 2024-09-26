/****** Object:  Table [PRODUCTS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PRODUCTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PRODUCTS](
	[PRODUCT_ID] [int] IDENTITY(1,1) NOT NULL,
	[MAIN_ID] [int] NULL,
	[NAME] [varchar](255) NOT NULL,
	[NAME_PRINT] [nvarchar](max) NULL,
	[STATUS_ID] [int] NOT NULL DEFAULT ((0)),
	[MOL_ID] [int] NULL,
	[ADMIN_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[TAGS] [varchar](max) NULL,
	[GROUP1_ID] [int] NULL,
	[GROUP2_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[EXTERN_ID] [varchar](32) NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[TYPE_ID] [int] NOT NULL DEFAULT ((0)),
	[CLASS_ID] [int] NULL,
	[PARENT_ID] [int] NULL,
	[UNIT_ID] [int] NULL,
	[ARTICLE_NUMBER] [varchar](50) NULL,
	[INNER_NUMBER] [varchar](50) NULL,
	[PLAN_GROUP_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[PRODUCT_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO
/****** Object:  Index [IX_PRODUCTS_NAME]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PRODUCTS]') AND name = N'IX_PRODUCTS_NAME')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PRODUCTS_NAME] ON [PRODUCTS]
(
	[NAME] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
