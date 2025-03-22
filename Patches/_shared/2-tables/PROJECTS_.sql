IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS](
	[PROJECT_ID] [int] IDENTITY(1,1) NOT NULL,
	[GROUP_ID] [int] NULL DEFAULT ((0)),
	[NAME] [varchar](255) NOT NULL,
	[GOAL] [varchar](max) NULL,
	[CURATOR_ID] [int] NOT NULL,
	[ADMIN_ID] [int] NOT NULL,
	[CHIEF_ID] [int] NOT NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[D_TO_MIN] [datetime] NULL,
	[STATUS_ID] [int] NOT NULL,
	[NOTE] [varchar](max) NULL,
	[CCY_ID] [varchar](3) NULL DEFAULT ('RUR'),
	[PLAN_CCY] [decimal](18, 0) NULL,
	[FACT_CCY] [decimal](18, 0) NULL,
	[PROGRESS] [decimal](3, 2) NULL DEFAULT ((0)),
	[PROGRESS_CRITICAL] [decimal](3, 2) NULL DEFAULT ((0)),
	[PROGRESS_EXEC] [decimal](3, 2) NULL DEFAULT ((0)),
	[PROGRESS_SPEED] [decimal](3, 2) NULL DEFAULT ((0)),
	[PROGRESS_LAG] [int] NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] NOT NULL DEFAULT (getdate()),
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[D_TO_FORECAST] [datetime] NULL,
	[LOCK_DATE] [datetime] NULL,
	[LOCK_MOL_ID] [int] NULL,
	[CALC_LOOPS] [int] NULL,
	[REFKEY] [varchar](250) NULL,
	[FOLDER_ID] [int] NULL,
	[TEMPLATE_NAME] [varchar](64) NULL,
	[TEMPLATE_ID] [int] NULL,
	[CALC_MODE_ID] [int] NOT NULL DEFAULT ((1)),
	[BUDGET_TYPE_ID] [int] NOT NULL DEFAULT ((1)),
	[SUBJECT_ID] [int] NULL,
	[CONTRACT_CCY_ID] [char](3) NULL DEFAULT ('RUR'),
	[CONTRACT_VALUE_CCY] [decimal](18, 2) NULL,
	[TYPE_ID] [int] NOT NULL DEFAULT ((1)),
	[AGENT_ID] [int] NULL,
	[NUMBER] [varchar](50) NULL,
	[PARENT_ID] [int] NULL,
	[IS_SHARED] [bit] NULL,
	[D_TODAY] [datetime] NULL,
	[CALENDAR_ID] [int] NULL,
	[CONTENT] [varchar](max) NULL,
	[SUPPLY] [varchar](max) NULL,
	[AREAS] [varchar](max) NULL,
	[TAGS] [varchar](max) NULL,
	[STATUS_TALK_ID] [int] NULL,
	[STATUS_HIST_ID] [int] NULL,
	[MX_DATE] [date] NULL,
	[MX_EV] [float] NULL,
	[MX_PV] [float] NULL,
	[MX_AC] [float] NULL,
	[MX_CV] [float] NULL,
	[MX_SV] [float] NULL,
	[MX_CPI] [float] NULL,
	[MX_SPI] [float] NULL,
 CONSTRAINT [PK_PROJECTS] PRIMARY KEY CLUSTERED 
(
	[PROJECT_ID] ASC
)
)
END
GO


IF not EXISTS (SELECT * FROM sys.fulltext_indexes fti WHERE fti.object_id = OBJECT_ID(N'[PROJECTS]'))
CREATE FULLTEXT INDEX ON [PROJECTS](
[CONTENT] LANGUAGE 'English')
KEY INDEX [PK_PROJECTS]ON ([CATALOG], FILEGROUP [PRIMARY])
WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM)


GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_projects]'))
EXEC sp_executesql @statement = N'create trigger [tiu_projects] on [PROJECTS]
for insert, update
as begin
 
	set nocount on;

	if update(curator_id) or update(chief_id) or update(admin_id)
	begin
		update projects
		set curator_id = coalesce(nullif(curator_id,0), nullif(chief_id,0), nullif(admin_id,0), -25),
			chief_id = coalesce(nullif(chief_id,0), nullif(admin_id,0), -25),
			admin_id = coalesce(nullif(admin_id,0), nullif(chief_id,0), -25)
		where project_id in (select project_id from inserted)
	end
end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_projects_content]'))
EXEC sp_executesql @statement = N'create trigger [tiu_projects_content] on [PROJECTS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	-- update content
	update p
	set content = concat(			
			p.name, ''#'',
			p2.name, ''#'',
			subj.name, ''#'',
			ag.name, ''#'',
			mols.name, ''#'',
			p.note)
	from projects p
		left join projects p2 on p2.project_id = p.parent_id
		left join subjects subj on subj.subject_id = p.subject_id
		left join agents ag on ag.agent_id = p.agent_id
		join mols on mols.mol_id = p.chief_id
	where p.project_id in (
		select project_id from inserted
		)
		
end' 
GO
