
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_BUYS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_BUYS](
	[PROJECT_ID] [int] NOT NULL,
	[BUY_ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](200) NULL,
	[VENDOR] [varchar](50) NULL,
	[NOTE] [varchar](max) NULL,
	[QUANTITY] [decimal](18, 2) NULL,
	[NETTO] [decimal](18, 3) NULL,
	[BRUTTO] [decimal](18, 3) NULL,
	[PRICE_RUR] [decimal](18, 2) NULL,
	[PLAN_RUR] [decimal](18, 2) NULL,
	[PARENT_ID] [int] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[SORT_ID] [float] NULL,
	[LEVEL_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[MOL_ID] [int] NULL,
	[RESERVED_ID] [int] NULL,
	[NODE] [hierarchyid] NULL,
PRIMARY KEY CLUSTERED 
(
	[BUY_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PROJECTS_BUYS]') AND name = N'IX_PROJECTS_BUYS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PROJECTS_BUYS] ON [PROJECTS_BUYS]
(
	[PROJECT_ID] ASC,
	[BUY_ID] ASC
)
GO
