IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MOLS_STATUSES]') AND type in (N'U'))
CREATE TABLE [MOLS_STATUSES](
	[STATUS_ID] [int] PRIMARY KEY,
	[NAME] [varchar](50),
    [SHORT_NAME] [varchar](8),
    [IMG_URL] [varchar](256),
	[SORT] [int]
);