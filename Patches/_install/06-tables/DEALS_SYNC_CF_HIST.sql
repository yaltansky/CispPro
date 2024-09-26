/****** Object:  Table [DEALS_SYNC_CF_HIST]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS_SYNC_CF_HIST]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS_SYNC_CF_HIST](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[REPLICATE_DATE] [datetime] NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

