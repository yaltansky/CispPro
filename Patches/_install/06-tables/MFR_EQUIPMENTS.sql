/****** Object:  Table [MFR_EQUIPMENTS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_EQUIPMENTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_EQUIPMENTS](
	[SUBJECT_ID] [int] NULL,
	[EQUIPMENT_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NULL,
	[NUMBER] [varchar](100) NULL,
	[NAME] [varchar](250) NULL,
	[D_DOC] [datetime] NULL,
	[D_RELEASE] [datetime] NULL,
	[MODEL] [varchar](100) NULL,
	[SPECIFICATION] [varchar](max) NULL,
	[PROP_POWER] [float] NULL,
	[MOL_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[CONTENT] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[NAME_LIST] [varchar](250) NULL,
	[PRICE_HOUR] [decimal](18, 2) NULL,
	[BALANCE_VALUE] [decimal](18, 2) NULL,
	[MONTH_LOADING] [float] NULL,
	[RESOURCE_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[EQUIPMENT_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO
/****** Object:  Index [IX_MFR_EQUIPMENTS_NAME]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_EQUIPMENTS]') AND name = N'IX_MFR_EQUIPMENTS_NAME')
CREATE NONCLUSTERED INDEX [IX_MFR_EQUIPMENTS_NAME] ON [MFR_EQUIPMENTS]
(
	[SUBJECT_ID] ASC,
	[NAME] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Trigger [tiu_equipments_content]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_equipments_content]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tiu_equipments_content] on [MFR_EQUIPMENTS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	update x
	set name_list = left(concat(
			x.name, '' '',
			x.model,
			'' (№'', x.number, '')''
			), 250),
		content = concat(
			s.name, '' '', s.short_name, '' '',
			x.number, '' '',
			x.name, '' '',
			x.model, '' '',
			x.specification, '' '',
			x.note
			)
	from mfr_equipments x
		join subjects s on s.subject_id = x.subject_id
	where equipment_id in (select equipment_id from inserted)

end
' 
GO
