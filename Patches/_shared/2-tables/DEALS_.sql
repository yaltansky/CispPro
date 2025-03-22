
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEALS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEALS](
	[DEAL_ID] [int] NOT NULL,
	[EXTERNAL_ID] [int] NULL,
	[D_DOC] [datetime] NULL,
	[NUMBER] [varchar](50) NULL,
	[OWNER_ID] [int] NULL,
	[VENDOR_ID] [int] NULL,
	[APPOVAL_SHEET_NUMBER] [varchar](50) NULL,
	[APPOVAL_SHEET_DATE] [datetime] NULL,
	[CRM_NUMBER] [varchar](50) NULL,
	[CRM_DATE] [datetime] NULL,
	[DOGOVOR_NUMBER] [varchar](50) NULL,
	[DOGOVOR_DATE] [datetime] NULL,
	[SPEC_NUMBER] [varchar](50) NULL,
	[SPEC_DATE] [datetime] NULL,
	[CUSTOMER_ID] [int] NULL,
	[CUSTOMER_COUNTRY] [varchar](50) NULL,
	[CUSTOMER_CITY] [varchar](50) NULL,
	[CUSTOMER_TYPE_ID] [varchar](32) NULL,
	[CONSUMER_ID] [int] NULL,
	[CCY_ID] [char](3) NULL,
	[VALUE_CCY] [decimal](18, 2) NULL,
	[AGENT_SHIPPER_ID] [int] NULL,
	[DELIVERY_BASIS_ID] [varchar](32) NULL,
	[DELIVERY_BASIS_NOTE] [varchar](50) NULL,
	[DURATION_DELIVERY_FROM_ID] [varchar](32) NULL,
	[DURATION_DELIVERY] [int] NULL,
	[DELIVERY_DAYS_MOUNTING] [int] NULL,
	[DELIVERY_DAYS_SHIPPING] [int] NULL,
	[DURATION_MANUFACTURE] [int] NULL,
	[DURATION_RESERVESHIPPING] [int] NULL,
	[MANAGER_ID] [int] NULL,
	[EXTRA_CONDITIONS] [varchar](max) NULL,
	[NOTE] [varchar](max) NULL,
	[PRINCIPAL_AGENT_ID] [int] NULL,
	[MFR_NAME] [varchar](50) NULL,
	[BUDGET_ID] [int] NULL,
	[UID] [varbinary](32) NULL,
	[RATE_FIN] [float] NULL,
	[SUBJECT_ID] [int] NULL,
	[NDS_RATIO] [float] NULL,
	[VER_NUMBER] [varchar](20) NULL,
	[VER_DATE] [datetime] NULL,
	[STATUS_ID] [int] NULL,
	[CONTENT] [varchar](max) NULL,
	[BUH_PRINCIPAL_SPEC_NUMBER] [varchar](50) NULL,
	[LEFT_CCY] [decimal](18, 2) NULL,
	[NAME] [varchar](255) NULL,
	[DIRECTION_ID] [int] NULL,
	[D_CLOSED] [datetime] NULL,
	[PROGRAM_ID] [int] NULL,
	[BUH_PRINCIPAL_ID] [int] NULL,
	[BUH_PRINCIPAL_COMMISSION_NUMBER] [varchar](100) NULL,
	[DOGOVOR_ID] [int] NULL,
	[DOGOVOR_CCY_ID] [char](3) NULL,
	[SPEC_ID] [int] NULL,
	[DELIVERY_MISC_TERM] [varchar](255) NULL,
	[eProjectID] [int] NULL,
	[eProjectName] [varchar](50) NULL,
	[BUH_PRINCIPAL_NUMBER] [varchar](100) NULL,
	[ERRORS] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[BUH_PRINCIPAL_COMMISSION_ID] [int] NULL,
	[BUH_PRINCIPAL_SPEC_ID] [int] NULL,
	[PAY_CONDITIONS] [varchar](50) NULL,
 CONSTRAINT [PK_DEALS] PRIMARY KEY CLUSTERED 
(
	[DEAL_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DEALS]') AND name = N'IX_DEALS_EXTERNAL')
CREATE NONCLUSTERED INDEX [IX_DEALS_EXTERNAL] ON [DEALS]
(
	[EXTERNAL_ID] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DEALS]') AND name = N'IX_DEALS_SUBJECTS')
CREATE NONCLUSTERED INDEX [IX_DEALS_SUBJECTS] ON [DEALS]
(
	[SUBJECT_ID] ASC,
	[BUDGET_ID] ASC
)
GO

IF not EXISTS (SELECT * FROM sys.fulltext_indexes fti WHERE fti.object_id = OBJECT_ID(N'[DEALS]'))
CREATE FULLTEXT INDEX ON [DEALS](
[CONTENT] LANGUAGE 'English')
KEY INDEX [PK_DEALS]ON ([CATALOG], FILEGROUP [PRIMARY])
WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM)


GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_deals_content]'))
EXEC sp_executesql @statement = N'create trigger [tiu_deals_content] on [DEALS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	update x
	set content = concat(
			s.name, '' '', s.short_name, '' '',
			st.name, '' '',
			x.buh_principal_number, '' '',
			x.number, '' '',
			x.dogovor_number, '' '',
			x.spec_number, '' '',
			ag.name, '' '',
			ag2.name, '' '',
			x.note
			)
	from deals x
		left join subjects s on s.subject_id = x.vendor_id
		left join deals_statuses st on st.status_id = x.status_id
		left join agents ag on ag.agent_id = x.customer_id
		left join agents ag2 on ag2.agent_id = x.consumer_id
	where deal_id in (select deal_id from inserted)

end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_deals]'))
EXEC sp_executesql @statement = N'create trigger [tu_deals] on [DEALS]
for update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	if update(status_id)
		update p
		set status_id = i.status_id
		from projects p
			join inserted i on i.deal_id = p.project_id

	if update(subject_id)
		update p
		set subject_id = i.subject_id
		from projects p
			join inserted i on i.deal_id = p.project_id

	if update(number) or update(customer_id)
	begin
		update d
		set name = isnull(d.number, '''') + '' '' + isnull(a.name, '''')
		from deals d
			join inserted i on i.deal_id = d.deal_id
			left join agents a on a.agent_id = d.customer_id

		update p
		set name = i.name
		from projects p
			join inserted i on i.deal_id = p.project_id
		where i.name is not null
	end

	if update(manager_id)
		update p
		set chief_id = i.manager_id
		from projects p
			join inserted i on i.deal_id = p.project_id

end
' 
GO
