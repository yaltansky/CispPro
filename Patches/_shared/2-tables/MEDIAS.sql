
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MEDIAS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MEDIAS](
	[MEDIA_ID] [int] NOT NULL,
	[NAME] [varchar](250) NOT NULL,
	[URL_TITLE] [varchar](max) NULL,
	[URL_FILE] [varchar](max) NULL,
	[DESCRIPTION] [varchar](max) NULL,
	[TAGS] [varchar](max) NULL,
	[NODE] [hierarchyid] NULL,
	[PARENT_ID] [int] NULL,
	[LEVEL_ID] [int] NULL DEFAULT ((0)),
	[SORT_ID] [float] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[MEDIA_ID] ASC
)
)
END
GO

