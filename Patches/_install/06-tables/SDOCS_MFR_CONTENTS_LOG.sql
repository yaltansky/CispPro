/****** Object:  Table [SDOCS_MFR_CONTENTS_LOG]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_CONTENTS_LOG]') AND type in (N'U'))
BEGIN
CREATE TABLE [SDOCS_MFR_CONTENTS_LOG](
	[TRAN_ID] [uniqueidentifier] NULL,
	[TRAN_CALLER] [varchar](max) NULL,
	[TRAN_USER_ID] [int] NULL,
	[TRAN_DATE] [datetime] NOT NULL DEFAULT getdate(),
	[CONTENT_ID] [int] NULL,
	[OLD_MANAGER_ID] [int] NULL,
	[NEW_MANAGER_ID] [int] NULL
)
END
GO
