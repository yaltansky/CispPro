if object_id('projects_timesheetsall_news') is not null drop proc projects_timesheetsall_news
go
-- exec projects_timesheetsall_news 502
create proc projects_timesheetsall_news
	@mol_id int,
	@project_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
	@search nvarchar(100) = null
as
begin

    set nocount on;
	
-- calc (if needed)	
	declare @last_d_calc datetime = isnull((
		select max(calc_date) from projects_timesheets
		where (@project_id is null or project_id = @project_id)
			and (@mol_id is null or mol_id = @mol_id)
		), 0)
	if datediff(minute, @last_d_calc, getdate()) > 5 exec projects_timesheets_calc @project_id = @project_id, @mol_id = @mol_id

-- @search
	set @search = '%' + replace(@search, ' ', '%') + '%'

	declare @today datetime = dbo.today()
	declare @ids as app_pkids
	insert into @ids select distinct x.timesheet_id
	from projects_timesheets_days x
		join projects_timesheets xx on xx.timesheet_id = x.timesheet_id
	where x.d_doc between isnull(@d_from, @today) and isnull(@d_to, @today)
		and xx.mol_id = @mol_id
		and (@project_id is null or xx.project_id = @project_id)

-- @where
	declare @where nvarchar(max) = concat(' where
			(x.mol_id = @mol_id)
		and (@project_id is null or x.project_id = @project_id)
		and not exists(select 1 from @ids where id = x.timesheet_id)
		'
		-- @d_from
		, case when @d_from is not null then ' and (x.d_to >= @d_from)' end
		-- @d_to
		, case when @d_to is not null then ' and (x.d_to <= @d_to)' end
		-- @search
		, case
			when @search is not null then ' and (x.name like @search)'
		  end
		)

-- @fields
	declare @fields nvarchar(max) = N'		
		@mol_id int,
		@project_id int,
		@d_from datetime,
		@d_to datetime,
		@search nvarchar(100),
		@ids app_pkids readonly
	'

-- @sql
	declare @sql nvarchar(max) = N'select * from projects_timesheetsall x ' + @where

    exec sp_executesql @sql, @fields,
        @mol_id, @project_id, @d_from, @d_to, @search, @ids

end
go
