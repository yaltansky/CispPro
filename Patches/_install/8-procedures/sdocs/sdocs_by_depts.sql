if object_id('sdocs_by_depts_calc') is not null drop proc sdocs_by_depts_calc
go
create proc sdocs_by_depts_calc
	@type_id int
as
begin
	
	set nocount on;

	create table #sdocs(
		dept_name varchar(100),
		agent_name varchar(250),
		doc_id int primary key,
		doc_name varchar(250),
	)

	declare @min_id int = (select min(doc_id) from sdocs)

	insert into #sdocs(dept_name, agent_name, doc_id, doc_name)
	select 
		isnull(dp.name, '-'),
		ltrim(rtrim(isnull(ag.name, '-'))),
		x.doc_id,
		case 
			when d.number is not null and d.number <> x.number then concat(x.number, ' > БС №', d.number)
			else x.number
		end
	from (
		select doc_id, deal_id, number from sdocs 
		where type_id = @type_id and status_id not in (-1, 0)
		union select 0, 0, '<неопределено>'
		) x		
		left join deals d on d.deal_id = x.deal_id
			left join depts dp on dp.dept_id = d.direction_id
			left join agents ag on ag.agent_id = d.customer_id
			left join mols on mols.mol_id = d.manager_id
	
	delete from sdocs_by_depts

	-- dept_name
	insert into sdocs_by_depts(doc_id, name)
	select
		@min_id - (row_number() over (order by name) + 1),
		x.name
	from (
		select distinct dept_name as name from #sdocs
		) x

	-- agent_name
	set @min_id = (select min(doc_id) from sdocs_by_depts)
	insert into sdocs_by_depts(parent_id, doc_id, name)
	select
		x.parent_id,
		@min_id - (row_number() over (order by name) + 1),
		x.name
	from (
		select distinct sx.doc_id as parent_id, agent_name as name
		from #sdocs s
			join sdocs_by_depts sx on sx.name = s.dept_name
		) x

	-- docs
	insert into sdocs_by_depts(parent_id, doc_id, name)
	select sx2.doc_id, x.doc_id, x.doc_name
	from #sdocs x
		join sdocs_by_depts sx1 on sx1.name = x.dept_name and sx1.parent_id is null
			join sdocs_by_depts sx2 on sx2.parent_id = sx1.doc_id and sx2.name = x.agent_name

	exec tree_calc_nodes 'sdocs_by_depts', 'doc_id', @sortable = 0

	drop table #sdocs
end
go

-- exec sdocs_replicate
-- exec sdocs_by_depts_calc 1
