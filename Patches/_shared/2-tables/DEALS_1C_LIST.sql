
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
)
)
END
GO

