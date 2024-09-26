/****** Object:  Table [DOC_TYPES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DOC_TYPES]') AND type in (N'U'))
BEGIN
CREATE TABLE [DOC_TYPES](
	[TYPE] [int] NULL,
	[DIRECTION] [int] NULL,
	[NAME] [varchar](100) NULL
) ON [PRIMARY]
END
GO

