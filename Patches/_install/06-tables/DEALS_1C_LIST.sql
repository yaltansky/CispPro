/****** Object:  Table [DEALS_1C_LIST]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS_1C_LIST]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS_1C_LIST](
	[BS] [varchar](100) NOT NULL,
	[LPDate] [datetime] NULL,
	[Date1C] [datetime] NULL,
	[Comment] [varchar](255) NULL,
PRIMARY KEY CLUSTERED 
(
	[BS] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

