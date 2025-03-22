if object_id('findocs_accounts_view') is not null drop proc findocs_accounts_view
go
create proc findocs_accounts_view
	@search varchar(250) = null,
	@subject_id int = null,
	@parent_id int = null,
	@extra_id int = null
as
begin

	set nocount on;

	declare @result table (account_id int, node hierarchyid)

	if @parent_id is not null
	begin
		insert into @result
		select account_id, node
		from findocs_accounts
		where parent_id = @parent_id
	end
	
	else begin
		declare @id int

		if dbo.hashid(@search) is not null
		begin
			set @id = dbo.hashid(@search)
			set @search = null
		end

		set @search = '%' + replace(@search, ' ', '%') + '%'
		declare @today datetime = dbo.today()
		declare @yesterday datetime = dbo.work_day_add(@today, -1)

		insert into @result
			select account_id, node
			from findocs_accounts
			where (@id is null or account_id = @id)
				and (@search is null or (
					name like @search
					or number like @search
					))
				and (@subject_id is null or subject_id = @subject_id)
				and ((@extra_id is null and is_deleted = 0)
					-- id: -1, name: 'Удалено'
					or (@extra_id = -1 and (is_deleted = 1))
					-- id: 1, name: 'Обработано сегодня'
					or (@extra_id = 1 and (last_d_upload >= @today))
					-- id: 2, name: 'Обработано вчера'
					or (@extra_id = 2 and (dbo.getday(last_d_upload) = @yesterday))					
					-- id: 3, name: 'Обработано давно'
					or (@extra_id = 3 and (isnull(last_d_upload,0) < @yesterday))
					)

		-- get all parents
		insert into @result(account_id, node)
			select distinct x.account_id, x.node
			from findocs_accounts x
				inner join @result r on r.node.IsDescendantOf(x.node) = 1
			where x.has_childs = 1
				and x.is_deleted = 0
	end

-- #result
	select
		x.*,
		SUBJECT_NAME = s.SHORT_NAME
	into #result
	from findocs_accounts x
		left join subjects s on s.subject_id = x.subject_id
	where x.account_id in (select account_id from @result)

-- calc totals
	update x
	set saldo_in = xx.saldo_in,
		saldo_out = xx.saldo_out,
		last_d_doc = xx.last_d_doc,
		last_d_upload = xx.last_d_upload
	from #result x
		join (
			select
				r.node_id,
				sum(r2.saldo_in) as saldo_in,
				sum(r2.saldo_out) as saldo_out,
				max(r2.last_d_doc) as last_d_doc,
				max(r2.last_d_upload) as last_d_upload
			from #result r
				join #result r2 on r2.node.IsDescendantOf(r.node) = 1
			group by r.node_id
		) xx on xx.node_id = x.node_id
	where x.has_childs = 1

-- select
	select * from #result order by node, name

-- drop
	drop table #result
end
GO
