/****** Object:  Table [PAYS_SALDO]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PAYS_SALDO]') AND type in (N'U'))
BEGIN
CREATE TABLE [PAYS_SALDO](
	[ACCOUNT_ID] [int] NOT NULL,
	[SALDO_IN] [decimal](18, 2) NULL,
	[D_DOC] [datetime] NOT NULL,
	[EXTERNAL_ID] [int] NOT NULL,
 CONSTRAINT [PK_PAYS_SALDO] PRIMARY KEY CLUSTERED 
(
	[ACCOUNT_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
