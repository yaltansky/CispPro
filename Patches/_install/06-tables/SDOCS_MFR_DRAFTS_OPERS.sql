/****** Object:  Table [SDOCS_MFR_DRAFTS_OPERS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_DRAFTS_OPERS]') AND type in (N'U'))
BEGIN
CREATE TABLE [SDOCS_MFR_DRAFTS_OPERS](
	[OPER_ID] [int] IDENTITY(1,1) NOT NULL,
	[DRAFT_ID] [int] NULL,
	[NUMBER] [int] NULL,
	[PLACE_ID] [int] NULL,
	[TYPE_ID] [int] NULL,
	[NAME] [varchar](100) NULL,
	[PREDECESSORS] [varchar](100) NULL,
	[DURATION] [float] NULL,
	[DURATION_ID] [int] NULL,
	[DURATION_WK] [float] NULL,
	[DURATION_WK_ID] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_DELETED] [bit] NULL,
	[COUNT_EXECUTORS] [int] NULL,
	[COUNT_RESOURCES] [int] NULL,
	[IS_FIRST] [bit] NULL,
	[IS_LAST] [bit] NULL,
	[IS_VIRTUAL] [bit] NULL,
	[RESERVED] [int] NULL,
	[COUNT_WORKERS] [int] NULL,
	[PERCENT_AUTOMATION] [float] NULL,
	[WORK_TYPE_ID] [int] NULL,
	[OPERKEY] [varchar](20) NULL,
	[VARIANT_NUMBER] [int] NULL,
	[VARIANT_SELECTED] [bit] NULL,
	[EXTERN_ID] [varchar](32) NULL,
PRIMARY KEY CLUSTERED 
(
	[OPER_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_SDOCS_MFR_DRAFTS_OPERS_KEY]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_DRAFTS_OPERS]') AND name = N'IX_SDOCS_MFR_DRAFTS_OPERS_KEY')
CREATE NONCLUSTERED INDEX [IX_SDOCS_MFR_DRAFTS_OPERS_KEY] ON [SDOCS_MFR_DRAFTS_OPERS]
(
	[DRAFT_ID] ASC,
	[OPERKEY] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Trigger [tg_sdocs_mfr_drafts_opers]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tg_sdocs_mfr_drafts_opers]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tg_sdocs_mfr_drafts_opers] on [SDOCS_MFR_DRAFTS_OPERS]
for insert, update, delete as
begin

	set nocount on;
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(work_type_id)
		update x set 
			work_type_1 = case when exists(select 1 from mfr_drafts_opers where draft_id = x.draft_id and work_type_id = 1 and isnull(is_deleted,0) = 0) then 1 end,
			work_type_2 = case when exists(select 1 from mfr_drafts_opers where draft_id = x.draft_id and work_type_id = 2 and isnull(is_deleted,0) = 0) then 1 end,
			work_type_3 = case when exists(select 1 from mfr_drafts_opers where draft_id = x.draft_id and work_type_id = 3 and isnull(is_deleted,0) = 0) then 1 end
		from mfr_drafts x
		where x.draft_id in (select draft_id from inserted)

	update x
	set opers_count = isnull(op.opers_count, 0),
		is_design = isnull(op.is_design, 0)
	from sdocs_mfr_drafts x
		left join (
			select draft_id,
				count(*) as opers_count,
				is_design = max(case when work_type_id = 4 then 1 else 0 end)
			from sdocs_mfr_drafts_opers
			group by draft_id
		) op on op.draft_id = x.draft_id
	where x.draft_id in (
		select draft_id from inserted
		union select draft_id from deleted
		)

end' 
GO
/****** Object:  Trigger [tid_sdocs_mfr_drafts_opers]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tid_sdocs_mfr_drafts_opers]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tid_sdocs_mfr_drafts_opers] on [SDOCS_MFR_DRAFTS_OPERS]
for insert, delete as
begin

	set nocount on;

	update x
	set opers_count = isnull(op.opers_count, 0)
	from sdocs_mfr_drafts x
		left join (
			select draft_id, count(*) as opers_count
			from sdocs_mfr_drafts_opers
			group by draft_id
		) op on op.draft_id = x.draft_id
	where x.draft_id in (
		select draft_id from inserted
		union select draft_id from deleted
		)
end
' 
GO
