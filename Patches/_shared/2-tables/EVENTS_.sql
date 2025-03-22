
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EVENTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [EVENTS](
	[PARENT_ID] [int] NULL,
	[EVENT_ID] [int] IDENTITY(1,1) NOT NULL,
	[FEED_ID] [int] NOT NULL DEFAULT ((1)),
	[FEED_TYPE_ID] [int] NULL,
	[PRIORITY_ID] [int] NULL,
	[STATUS_ID] [int] NOT NULL DEFAULT ((0)),
	[NAME] [varchar](255) NOT NULL,
	[CONTENT] [varchar](max) NOT NULL,
	[HREF] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[MOL_ID] [int] NULL DEFAULT ((-25)),
	[RESERVED] [varchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[EVENT_ID] ASC
)
)
END
GO

