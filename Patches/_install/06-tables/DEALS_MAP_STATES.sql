/****** Object:  Table [DEALS_MAP_STATES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS_MAP_STATES]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS_MAP_STATES](
	[State] [int] NULL,
	[STATUS_ID] [int] NULL
) ON [PRIMARY]
END
GO
