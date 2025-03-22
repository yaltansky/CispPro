if object_id('plan_pays_view') is not null
	drop procedure plan_pays_view
go
-- exec plan_pays_view 1000
create proc plan_pays_view
	@mol_id int,
	@period_id varchar(16) = null,	
	@direction_id int = null,
	@manager_id int = null,
	@status_id int = null,
	@search varchar(100) = null,
	@folder_id int = null,
	--
	@sort_expression varchar(50) = null,
	@offset int = 0,
	@fetchrows int = 30,
	@rowscount int = null out
as
begin
	
	set nocount on;
	
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Admin,Finance.Plans.Admin,Finance.Plans.Reader')
	
-- @plan_pay_id
	declare @plan_pay_id int
	if dbo.hashid(@search) is not null
	begin
		set @plan_pay_id = dbo.hashid(@search)
		set @search = null
	end

-- @search
	set @search = '%' + @search + '%'

-- reglament
	declare @managers as app_pkids
	declare @depts as app_pkids
	if @is_admin = 0
	begin
        insert into @depts select dept_id from depts where chief_id = @mol_id
		insert into @managers select mol_id from mols where @mol_id in (mol_id, chief_id)
	end

-- @folder_id	
	declare @ids as app_pkids
	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)
	if @folder_id is not null insert into @ids exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'plp'

-- prepare sql
	declare @sql nvarchar(max), @fields nvarchar(max)

	declare @where nvarchar(max) = N' where (1=1)'
		+ case
			when @is_admin = 1 then ' '
			else ' and (
				exists(select 1 from @managers where id = x.mol_id)
                or exists(select 1 from @depts where id = x.direction_id)
				)'
		  end
		-- @plan_pay_id
		+ case
			when @plan_pay_id is not null then concat(' and (x.plan_pay_id = ', @plan_pay_id, ')')
			else ' '
		  end
		-- @period_id
		+ case 
			when @period_id is not null then ' and (x.period_id = @period_id)' 
			else ' '
		  end
		-- @direction_id
		+ case
			when @direction_id is not null then ' and (x.direction_id = @direction_id)'
			else ' '
		  end
		-- @manager_id
		+ case
			when @manager_id is not null then ' and (x.mol_id = @manager_id)'
			else ' '
		  end
		-- @status_id
		+ case 
			when @status_id is not null then ' and (x.status_id = @status_id)' 
			else 
				case 
					when @folder_id is null then ' and (x.status_id not in (-1,20))'
					else ' '
				end
		  end
		-- @search
		+ case
			when @search is not null then 'and (x.content like @search)'
			else ' '
		  end

	declare @fields_base nvarchar(max) = N'
		@period_id varchar(16),
		@direction_id int,
		@manager_id int,
		@status_id int,
		@search nvarchar(100),
		@depts app_pkids readonly,
		@managers app_pkids readonly,
		@ids app_pkids readonly
	'

	declare @inner nvarchar(max) = N'
	left join plan_pays_statuses statuses on statuses.status_id = x.status_id
	left join depts d on d.dept_id = x.direction_id
	left join mols chiefs on chiefs.mol_id = x.chief_id
	left join mols on mols.mol_id = x.mol_id
	'
	+ case when @folder_id is null then '' else 'join @ids ids on ids.id = x.plan_pay_id ' end

	-- @rowscount
	set @sql = N'select @rowscount = count(*) from plan_pays x ' + @inner + @where
	set @fields = @fields_base + ', @rowscount int out'

	print 'count(*): ' + @sql + char(10)

	exec sp_executesql @sql, @fields,
		@period_id, @direction_id, @manager_id, @status_id, @search,		
		@depts, @managers, @ids,
		@rowscount out
		
	-- @order_by
	declare @order_by nvarchar(50) = N' order by ' + isnull(@sort_expression, 'x.d_doc desc, x.number')

	-- @sql
	set @sql = N'
	select 
		X.PLAN_PAY_ID,
		X.PERIOD_ID,
		X.D_DOC,
		X.STATUS_ID,
		STATUSES.NAME AS STATUS_NAME,
		ISNULL(D.SHORT_NAME, ''? '' + D.NAME) AS DIRECTION_NAME,
		CHIEFS.NAME AS CHIEF_NAME,
		MOLS.NAME AS MOL_NAME,
		X.NUMBER,
		X.VALUE_PLAN,
		X.VALUE_FACT,
		X.NOTE
	from plan_pays x '
	+ @inner + @where + @order_by
	+ ' offset @offset rows fetch next @fetchrows rows only'

	set @fields = @fields_base + ', @offset int, @fetchrows int'

	print '@sql: ' + @sql + char(10)

	exec sp_executesql @sql, @fields,
		@period_id, @direction_id, @manager_id, @status_id, @search,		
		@depts, @managers, @ids,
		@offset, @fetchrows

end
go
