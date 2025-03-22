
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_REPS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_REPS](
	[PROJECT_ID] [int] NULL,
	[REP_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NULL DEFAULT ((0)),
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[NEXT_D_FROM] [datetime] NULL,
	[NEXT_D_TO] [datetime] NULL,
	[NAME] [varchar](100) NULL,
	[NOTE] [varchar](max) NULL,
	[MOL_ID] [int] NULL,
	[D_CALC] [datetime] NULL,
	[REP_TYPE_ID] [int] NULL DEFAULT ((1)),
	[ADD_DATE] [datetime] NOT NULL DEFAULT (getdate()),
PRIMARY KEY CLUSTERED 
(
	[REP_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_projects_reps]'))
EXEC sp_executesql @statement = N'
create trigger [ti_projects_reps] on [PROJECTS_REPS]
for insert
as
begin

	set nocount on;

	declare @d_from datetime; set @d_from = dbo.week_start(dbo.today())
	declare @d_to datetime; set @d_to = @d_from + 6
	declare @next_d_from datetime; set @next_d_from = dbo.week_start(dbo.today()+7)
	declare @next_d_to datetime; set @next_d_to = @next_d_from + 6

	update projects_reps
	set status_id = isnull(status_id, 0),
		d_from = isnull(d_from, @d_from),
		d_to = isnull(d_to, @d_to),
	    next_d_from = isnull(next_d_from, @next_d_from),
		next_d_to = isnull(next_d_to, @next_d_to),
		name = isnull(name, ''Промежуточный отчёт, неделя #'' + cast(datepart(week, isnull(d_from, @d_from)) as varchar)),
		d_calc = dbo.today()
	where rep_id in (select rep_id from inserted)

end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_projects_reps]'))
EXEC sp_executesql @statement = N'
create trigger [tu_projects_reps] on [PROJECTS_REPS]
for update
as
begin

	set nocount on;

	if update(d_from) or update(d_to)
	begin
		declare @rep_type_id int

		update r
		set @rep_type_id = 
				case
					when dateadd(ww, 1, r.d_from) - 1 = d_to then 1
					when dateadd(m, 1, r.d_from) - 1 = d_to then 2
					else 3
				end,
			name = 
				case
					when @rep_type_id = 1 then ''Оперативный план, неделя #'' + cast(datepart(iso_week, r.d_from) as varchar)
					when @rep_type_id = 2 then ''Оперативный план, '' + dbo.month_name(r.d_from)
					when @rep_type_id = 3 then ''Оперативный план, интервал #''
				end,
			rep_type_id = @rep_type_id
		from projects_reps r
		where r.rep_id in (select rep_id from inserted)
	end

end
' 
GO
