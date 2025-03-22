
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FINDOCS_UPLOAD_DETAILS2]') AND type in (N'U'))
BEGIN
CREATE TABLE [FINDOCS_UPLOAD_DETAILS2](
	[RowId] [int] IDENTITY(1,1) NOT NULL,
	[PayId] [int] NULL,
	[ARTICLE_ID] [int] NULL,
	[MfrName] [varchar](50) NULL,
	[ArticleName] [varchar](250) NULL,
	[ValueCcy] [decimal](18, 2) NULL,
PRIMARY KEY CLUSTERED 
(
	[RowId] ASC
)
)
END
GO

