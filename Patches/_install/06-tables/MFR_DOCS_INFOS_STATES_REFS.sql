/****** Object:  Table [MFR_DOCS_INFOS_STATES_REFS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_DOCS_INFOS_STATES_REFS]') AND type in (N'U'))
BEGIN

CREATE TABLE [MFR_DOCS_INFOS_STATES_REFS](
	[STATE_ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](50) NULL,
	[NOTE] [varchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[STATE_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)

INSERT INTO MFR_DOCS_INFOS_STATES_REFS(NAME)
VALUES ('Размещение заказа'), ('Разработка КД'), ('Обеспечение материалами'), ('Начало производства'), ('Завершение производства')

END
GO

