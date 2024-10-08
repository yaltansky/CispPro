USE [CISP_SHARED]
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DOCUMENTS_DICT_ROUTES_POINTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DOCUMENTS_DICT_ROUTES_POINTS](
	[DICT_POINT_ID] [int] IDENTITY(1,1) NOT NULL,
	[DICT_ROUTE_ID] [int] NOT NULL,
	[NAME] [nvarchar](50) NULL,
	[MOL_ID] [int] NULL,
	[RESPONSIBLE_ID] [int] NULL,
	[NOTE] [nvarchar](max) NULL,
	[ALLOW_REJECT] [bit] NULL,
	[ADD_DATE] [datetime] NULL,
	[IS_DELETED] [bit] NOT NULL,
 CONSTRAINT [PK_DOCUMENTS_DICT_ROUTES_POINTS] PRIMARY KEY CLUSTERED 
(
	[DICT_POINT_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
END
GO
