/****** Object:  Table [SDOCS_MFR_DRAFTS_OPERS_RESOURCES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_DRAFTS_OPERS_RESOURCES]') AND type in (N'U'))
BEGIN
CREATE TABLE [SDOCS_MFR_DRAFTS_OPERS_RESOURCES](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[DRAFT_ID] [int] NULL,
	[OPER_ID] [int] NULL,
	[RESOURCE_ID] [int] NULL,
	[EQUIPMENT_ID] [int] NULL,
	[LOADING] [float] NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_DELETED] [bit] NULL,
	[LOADING_PRICE] [float] NULL,
	[LOADING_VALUE] [decimal](18, 2) NULL,
 CONSTRAINT [PK_SDOCS_MFR_DRAFTS_OPERS_RESOURCES] PRIMARY KEY NONCLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Index [IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_DRAFTS_OPERS_RESOURCES]') AND name = N'IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES')
CREATE CLUSTERED INDEX [IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES] ON [SDOCS_MFR_DRAFTS_OPERS_RESOURCES]
(
	[DRAFT_ID] ASC,
	[OPER_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES_OPER]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_DRAFTS_OPERS_RESOURCES]') AND name = N'IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES_OPER')
CREATE NONCLUSTERED INDEX [IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES_OPER] ON [SDOCS_MFR_DRAFTS_OPERS_RESOURCES]
(
	[OPER_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES_RESOURCE_ID]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_DRAFTS_OPERS_RESOURCES]') AND name = N'IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES_RESOURCE_ID')
CREATE NONCLUSTERED INDEX [IX_SDOCS_MFR_DRAFTS_OPERS_RESOURCES_RESOURCE_ID] ON [SDOCS_MFR_DRAFTS_OPERS_RESOURCES]
(
	[RESOURCE_ID] ASC
)
INCLUDE ( 	[OPER_ID],
	[LOADING_VALUE]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Trigger [tg_sdocs_mfr_drafts_opers_resources]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tg_sdocs_mfr_drafts_opers_resources]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tg_sdocs_mfr_drafts_opers_resources] on [SDOCS_MFR_DRAFTS_OPERS_RESOURCES]
for insert, update, delete as
begin

	set nocount on;
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	update x
	set count_resources = xx.c_rows
	from sdocs_mfr_drafts_opers x
		left join (
			select oper_id, count(*) as c_rows
			from sdocs_mfr_drafts_opers_resources
			group by oper_id
		) xx on xx.oper_id = x.oper_id
	where x.oper_id in (
		select oper_id from inserted
		union select oper_id from deleted
		)
end' 
GO
