/****** Object:  Table [MFR_PLANS_JOBS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_PLANS_JOBS](
	[PLAN_JOB_ID] [int] IDENTITY(1,1) NOT NULL,
	[PLAN_ID] [int] NULL,
	[PLACE_ID] [int] NULL,
	[PLACE_TO_ID] [int] NULL,
	[D_DOC] [datetime] NULL,
	[NUMBER] [varchar](100) NULL,
	[STATUS_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[EXECUTOR_ID] [int] NULL,
	[REFKEY] [varchar](250) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[EXTERN_ID] [varchar](50) NULL,
	[TYPE_ID] [int] NOT NULL DEFAULT ((1)),
	[D_CLOSED] [datetime] NULL,
	[REPLICATE_DATE] [datetime] NULL,
	[HAS_CHILDS] [bit] NULL,
	[D_DOC_ROOT] [datetime] NULL,
	[SLICE] [uniqueidentifier] NULL,
	[SUBJECT_ID] [int] NULL,
	[AGENT_ID] [int] NULL,
	[CONTENT] [varchar](max) NULL,
 CONSTRAINT [PK_MFR_PLANS_JOBS] PRIMARY KEY CLUSTERED 
(
	[PLAN_JOB_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO
/****** Object:  Index [IX_MFR_PLANS_JOBS_1]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS]') AND name = N'IX_MFR_PLANS_JOBS_1')
CREATE NONCLUSTERED INDEX [IX_MFR_PLANS_JOBS_1] ON [MFR_PLANS_JOBS]
(
	[EXTERN_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_MFR_PLANS_JOBS_2]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS]') AND name = N'IX_MFR_PLANS_JOBS_2')
CREATE NONCLUSTERED INDEX [IX_MFR_PLANS_JOBS_2] ON [MFR_PLANS_JOBS]
(
	[SLICE] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
SET ANSI_PADDING ON

GO
/****** Object:  Index [IX_MFR_PLANS_JOBS_NUMBER]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS]') AND name = N'IX_MFR_PLANS_JOBS_NUMBER')
CREATE NONCLUSTERED INDEX [IX_MFR_PLANS_JOBS_NUMBER] ON [MFR_PLANS_JOBS]
(
	[NUMBER] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MFR_PLANS_JOBS_PLAN_ID]') AND parent_object_id = OBJECT_ID(N'[MFR_PLANS_JOBS]'))
ALTER TABLE [MFR_PLANS_JOBS]  WITH CHECK ADD  CONSTRAINT [FK_MFR_PLANS_JOBS_PLAN_ID] FOREIGN KEY([PLAN_ID])
REFERENCES [MFR_PLANS] ([PLAN_ID])
ON DELETE CASCADE
GO
IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MFR_PLANS_JOBS_PLAN_ID]') AND parent_object_id = OBJECT_ID(N'[MFR_PLANS_JOBS]'))
ALTER TABLE [MFR_PLANS_JOBS] CHECK CONSTRAINT [FK_MFR_PLANS_JOBS_PLAN_ID]
GO
/****** Object:  Trigger [ti_mfr_plan_job]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_mfr_plan_job]'))
EXEC dbo.sp_executesql @statement = N'create trigger [ti_mfr_plan_job] on [MFR_PLANS_JOBS]
for insert, update as
begin
	
	set nocount on;

	if update(plan_id) or update(plan_job_id)
		update mfr_plans_jobs
		set refkey = concat(''/mfrs/plans/'', plan_id, ''/jobs/'', plan_job_id)
		where plan_job_id in (select plan_job_id from inserted)

	if update(plan_id)
		update x set subject_id = pl.subject_id
		from mfr_plans_jobs x
			join mfr_plans pl on pl.plan_id = x.plan_id
		where plan_job_id in (select plan_job_id from inserted)

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(status_id)
	begin
		update x set fact_q = case when j.status_id = 100 then x.plan_q end
		from mfr_plans_jobs_details x
			join mfr_plans_jobs j on j.plan_job_id = x.plan_job_id
			join mfr_sdocs_opers o on o.oper_id = x.oper_id
		where x.plan_job_id in (select plan_job_id from inserted)
			and o.work_type_id = 4 -- Конструирование

		declare @jobs app_pkids; insert into @jobs select plan_job_id from mfr_plans_jobs
			where plan_job_id in (select plan_job_id from inserted)
				and status_id = 100
		if exists(select 1 from @jobs)
			exec mfr_plan_jobs_autofolder 2, @jobs = @jobs
	end
			
end
' 
GO
/****** Object:  Trigger [tu_mfr_plan_job_content]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_mfr_plan_job_content]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tu_mfr_plan_job_content] on [MFR_PLANS_JOBS]
for insert, update as
begin
	
	set nocount on;

	update x
	set content = concat(
			x.number, ''#''
			, pl.name, ''#''
			, x.note
			)
	from mfr_plans_jobs x
		left join mfr_places pl on pl.place_id = x.place_id
	where plan_job_id in (select plan_job_id from inserted)
end' 
GO
