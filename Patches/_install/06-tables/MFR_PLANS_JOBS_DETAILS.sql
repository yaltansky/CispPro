/****** Object:  Table [MFR_PLANS_JOBS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS_DETAILS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_PLANS_JOBS_DETAILS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PLAN_JOB_ID] [int] NULL,
	[MFR_DOC_ID] [int] NULL,
	[PRODUCT_ID] [int] NULL,
	[PARENT_ITEM_ID] [int] NULL,
	[PARENT_ITEM_Q] [float] NULL,
	[ITEM_ID] [int] NULL,
	[OPER_NUMBER] [int] NULL,
	[OPER_NAME] [varchar](100) NULL,
	[PREV_PLACE_ID] [int] NULL,
	[OPER_ID] [int] NULL,
	[PLAN_Q] [float] NULL,
	[FACT_Q] [float] NULL,
	[FACT_DEFECT_Q] [float] NULL,
	[DURATION_WK] [float] NULL,
	[DURATION_WK_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[UNIT_NAME] [varchar](20) NULL,
	[NDS_RATIO] [decimal](18, 4) NULL,
	[VALUE_PURE] [decimal](18, 2) NULL,
	[VALUE_NDS] [decimal](18, 2) NULL,
	[VALUE_RUR] [decimal](18, 2) NULL,
	[FROM_MFR_DOC_ID] [int] NULL,
	[CONTENT_ID] [int] NULL,
	[PLAN_DURATION_WK] [float] NULL,
	[PLAN_DURATION_WK_ID] [int] NULL,
	[RESERVED] [varchar](max) NULL,
	[COUNT_EXECUTORS] [int] NULL,
	[COUNT_RESOURCES] [int] NULL,
	[FACT_Q_LEFT] [float] NULL,
	[FACT_Q_TEMP] [float] NULL,
	[COUNT_EQUIPMENTS] [int] NULL,
	[PROBLEM_ID] [int] NULL,
	[RESOURCE_ID] [int] NULL,
	[NORM_DURATION] [float] NULL,
	[NORM_DURATION_WK] [float] NULL,
	[OVERLOADS_DURATION_WK] [float] NULL,
	[FLOW_ID] [int] NULL,
	[EXECUTORS_NAMES] [varchar](100) NULL,
	[NEXT_PLACE_ID] [int] NULL,
	[OPER_KEY] [varchar](20) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Index [IX_MFR_PLANS_JOBS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS_DETAILS]') AND name = N'IX_MFR_PLANS_JOBS_DETAILS')
CREATE NONCLUSTERED INDEX [IX_MFR_PLANS_JOBS_DETAILS] ON [MFR_PLANS_JOBS_DETAILS]
(
	[PLAN_JOB_ID] ASC,
	[OPER_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_MFR_PLANS_JOBS_DETAILS_ITEMS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS_DETAILS]') AND name = N'IX_MFR_PLANS_JOBS_DETAILS_ITEMS')
CREATE NONCLUSTERED INDEX [IX_MFR_PLANS_JOBS_DETAILS_ITEMS] ON [MFR_PLANS_JOBS_DETAILS]
(
	[PLAN_JOB_ID] ASC,
	[ITEM_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_MFR_PLANS_JOBS_DETAILS_ITOP]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS_DETAILS]') AND name = N'IX_MFR_PLANS_JOBS_DETAILS_ITOP')
CREATE NONCLUSTERED INDEX [IX_MFR_PLANS_JOBS_DETAILS_ITOP] ON [MFR_PLANS_JOBS_DETAILS]
(
	[ITEM_ID] ASC,
	[OPER_NUMBER] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_MFR_PLANS_JOBS_DETAILS2]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[MFR_PLANS_JOBS_DETAILS]') AND name = N'IX_MFR_PLANS_JOBS_DETAILS2')
CREATE NONCLUSTERED INDEX [IX_MFR_PLANS_JOBS_DETAILS2] ON [MFR_PLANS_JOBS_DETAILS]
(
	[CONTENT_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MFR_PLANS_JOBS_DETAILS_PLAN_JOB_ID2]') AND parent_object_id = OBJECT_ID(N'[MFR_PLANS_JOBS_DETAILS]'))
ALTER TABLE [MFR_PLANS_JOBS_DETAILS]  WITH CHECK ADD  CONSTRAINT [FK_MFR_PLANS_JOBS_DETAILS_PLAN_JOB_ID2] FOREIGN KEY([PLAN_JOB_ID])
REFERENCES [MFR_PLANS_JOBS] ([PLAN_JOB_ID])
ON DELETE CASCADE
GO
IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MFR_PLANS_JOBS_DETAILS_PLAN_JOB_ID2]') AND parent_object_id = OBJECT_ID(N'[MFR_PLANS_JOBS_DETAILS]'))
ALTER TABLE [MFR_PLANS_JOBS_DETAILS] CHECK CONSTRAINT [FK_MFR_PLANS_JOBS_DETAILS_PLAN_JOB_ID2]
GO
/****** Object:  Trigger [tiu_mfr_plan_job_details]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_mfr_plan_job_details]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tiu_mfr_plan_job_details] on [MFR_PLANS_JOBS_DETAILS]
for insert, update as
begin
	
	set nocount on;
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(plan_q)
		update x set 
			norm_duration_wk = x.norm_duration_wk * i.plan_q / nullif(d.plan_q,0),
			plan_duration_wk = x.plan_duration_wk * i.plan_q / nullif(d.plan_q,0)
		from mfr_plans_jobs_details x
			join deleted d on d.id = d.id
			join inserted i on i.id = x.id

	if update(problem_id)
		insert into mfr_plans_jobs_problems(detail_id, problem_id, note, add_mol_id, add_date)
		select i.id, i.problem_id, i.note, isnull(i.update_mol_id, i.add_mol_id), getdate()
		from inserted i
			left join deleted d on d.id = i.id
		where isnull(d.problem_id,0) != i.problem_id
			or isnull(d.note, '''') != isnull(i.note, '''')
end' 
GO
