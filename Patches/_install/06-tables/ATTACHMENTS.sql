/****** Object:  Table [ATTACHMENTS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[ATTACHMENTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [ATTACHMENTS](
	[KEY] [varchar](256) NOT NULL,
	[ATTACHMENTS] [xml] NULL,
PRIMARY KEY CLUSTERED 
(
	[KEY] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

