IF NOT EXISTS(SELECT 1 FROM SYS.TYPES WHERE NAME = 'APP_PKIDS')
CREATE TYPE [APP_PKIDS] AS TABLE(
	[ID] [int] NOT NULL,
	PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (IGNORE_DUP_KEY = OFF)
)
GO
