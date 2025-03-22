
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[BUDGETS_PERIODS]') AND type in (N'U'))
BEGIN
CREATE TABLE [BUDGETS_PERIODS](
	[BUDGET_PERIOD_ID] [int] IDENTITY(1,1) NOT NULL,
	[BUDGET_ID] [int] NOT NULL,
	[BDR_PERIOD_ID] [int] NULL,
	[NAME] [varchar](20) NULL,
	[DATE_START] [datetime] NULL,
	[DATE_END] [datetime] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[IS_SELECTED] [bit] NOT NULL DEFAULT ((0)),
	[IS_FIXED] [bit] NOT NULL DEFAULT ((0)),
PRIMARY KEY CLUSTERED 
(
	[BUDGET_PERIOD_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[td_budgets_periods]'))
EXEC sp_executesql @statement = N'create trigger [td_budgets_periods] on [BUDGETS_PERIODS]
for delete as
begin
	
	if exists(
		select 1
		from budgets_plans pl
			join deleted d on d.budget_id = pl.budget_id and d.budget_period_id = pl.budget_period_id
		)
	begin
		RAISERROR(''Невозможно удалить периоды, которые используются в планировании бюджета.'', 16, 1)
		ROLLBACK
	end
end' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_budgets_periods]'))
EXEC sp_executesql @statement = N'create trigger [tiu_budgets_periods] on [BUDGETS_PERIODS]
for insert, update as
begin
	
	update budgets_periods
	set name = isnull(x.name, y.name),
		date_start = y.date_start,
		date_end = y.date_end
	from budgets_periods x
		join bdr_periods y on y.bdr_period_id = x.bdr_period_id
		inner join inserted on inserted.bdr_period_id = x.bdr_period_id

	if exists(
		select 1
		from budgets_plans pl
			join inserted i on i.budget_id = pl.budget_id and i.budget_period_id = pl.budget_period_id
		where i.is_deleted = 1
			and pl.plan_rur != 0
		)
	begin
		RAISERROR(''Невозможно удалить периоды, которые используются в планировании бюджета.'', 16, 1)
		ROLLBACK
	end
end' 
GO
