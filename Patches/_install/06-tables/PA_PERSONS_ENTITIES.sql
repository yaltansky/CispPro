/****** Object:  Table [PA_PERSONS_ENTITIES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PA_PERSONS_ENTITIES]') AND type in (N'U'))
BEGIN
CREATE TABLE [PA_PERSONS_ENTITIES](
	[PERSON_ENTITY_ID] [int] IDENTITY(1,1) NOT NULL,
	[SUBJECT_ID] [int] NULL,
	[PERSON_ID] [int] NULL,
	[TABLE_NUMBER] [varchar](50) NULL,
	[NAME] [varchar](150) NULL,
	[ACCOUNT_TYPE_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL CONSTRAINT [DF__PA_PERSON__IS_DE__3B969E48]  DEFAULT ((0)),
	[STATUS_ID] [int] NULL CONSTRAINT [DF__PA_PERSON__STATU__424E88CF]  DEFAULT ((2)),
 CONSTRAINT [PK__PA_PERSO__44984A2AF7C0A5BE] PRIMARY KEY CLUSTERED 
(
	[PERSON_ENTITY_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

/****** Object:  Index [IX_PA_PERSONS_ENTITIES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PA_PERSONS_ENTITIES]') AND name = N'IX_PA_PERSONS_ENTITIES')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PA_PERSONS_ENTITIES] ON [PA_PERSONS_ENTITIES]
(
	[SUBJECT_ID] ASC,
	[PERSON_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Trigger [tiu_pa_persons_entities]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_pa_persons_entities]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tiu_pa_persons_entities] on [PA_PERSONS_ENTITIES]
for insert, update
as
begin

	set nocount on;

	update pe
	set name = p.name + '' '' + isnull(pe.table_number, '''')
	from pa_persons_entities pe
		inner join inserted i on i.person_entity_id = pe.person_entity_id
		inner join pa_persons p on p.person_id = pe.person_id

end
' 
GO
