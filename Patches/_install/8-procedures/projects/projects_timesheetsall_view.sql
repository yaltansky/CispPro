if object_id('projects_timesheetsall_view') is not null drop proc projects_timesheetsall_view
go
-- exec projects_timesheetsall_view 700, 502
create proc projects_timesheetsall_view
	@user_id int,
	@mol_id int,
	@project_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
	@search nvarchar(100) = null,
	@extra_id int = null,
		-- 1 - Текушие задачи
		-- 10 - Закрытые задачи
	@sort_expression varchar(50) = null
as
begin

    set nocount on;
	
	declare @is_admin bit = dbo.isinrole(@user_id, 'Admin,Projects.Admin')

-- @search
	set @search = '%' + replace(@search, ' ', '%') + '%'

-- prepare sql
	declare @sql nvarchar(max)

	declare @where nvarchar(max) = concat(' where
			x.mol_id = @mol_id
		and (@project_id is null or x.project_id = @project_id)
		'
		-- @is_admin
		, case
			when @is_admin = 0 then ' and (@user_id in (x.curator_id, x.chief_id, x.admin_id, x.mol_id))'
		  end
		-- @d_from
		, case when @d_from is not null then ' and (x.d_doc >= @d_from)' end
		-- @d_to
		, case when @d_to is not null then ' and (x.d_doc <= @d_to)' end
		-- @search
		, case
			when @search is not null then ' and (x.task_name like @search or x.project_name like @search)'
		  end
		-- @extra_id
		, case
			when @extra_id = 1 then ' and (isnull(x.is_closed,0) = 0)'
			when @extra_id = 10 then ' and (x.is_closed = 1)'
		  end
		  )

	declare @fields nvarchar(max) = N'		
		@user_id int,
		@mol_id int,
		@project_id int,
		@d_from datetime,
		@d_to datetime,
		@extra_id int,
		@search nvarchar(100)
	'

	declare @inner nvarchar(max) = N''

	-- @order_by
	declare @order_by nvarchar(100) = N' order by x.d_doc desc, x.project_name, x.task_name'
	if @sort_expression is not null set @order_by = N' order by ' + @sort_expression

	declare @subquery nvarchar(max) = 
		N'(select * from projects_timesheetsall_days x ' + @inner + @where +') x '

    -- @sql
    set @sql = N'select x.* from ' + @subquery + @order_by

    exec sp_executesql @sql, @fields,
        @user_id, @mol_id, @project_id, @d_from, @d_to, @extra_id, @search

end
go
