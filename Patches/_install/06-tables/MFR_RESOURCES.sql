/****** Object:  Table [MFR_RESOURCES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_RESOURCES]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_RESOURCES](
	[RESOURCE_ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](250) NULL,
	[NOTE] [varchar](max) NULL,
	[LIMIT_Q] [decimal](18, 3) NULL,
	[PRICE] [decimal](18, 2) NULL,
	[EXTERN_ID] [varchar](32) NULL,
	[IS_DELETED] [bit] NOT NULL CONSTRAINT [DF_MFR_RESOURCES_IS_DELETED]  DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[RESOURCE_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

