IF NOT EXISTS(SELECT 1 FROM SYS.TYPES WHERE NAME = 'APP_MAPIDS')
CREATE TYPE APP_MAPIDS AS TABLE(
	[ID] [INT] PRIMARY KEY CLUSTERED,
	[NEW_ID] INT
)
GO
