/****** Object:  Table [REGLAMENT_HIST]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[REGLAMENT_HIST]') AND type in (N'U'))
BEGIN
CREATE TABLE [REGLAMENT_HIST](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[KEY] [varchar](256) NULL,
	[MOL_ID] [int] NULL,
	[ACTION] [varchar](512) NULL,
	[TEXT] [varchar](512) NULL,
	[NOTE] [varchar](max) NULL,
	[TAG] [xml] NULL,
	[D_DOC] [datetime] NULL DEFAULT (getdate()),
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

