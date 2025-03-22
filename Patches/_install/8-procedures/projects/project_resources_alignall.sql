if object_id('project_resources_alignall') is not null drop proc project_resources_alignall
go

create proc project_resources_alignall
	@mol_id int,
	@tree_id int,
	@resource_id int,
	@d_from datetime = null
as
begin
	set nocount on;

	if @mol_id is null return -- nothing TODO

-- state
	declare @proc_name sysname = object_name(@@procid);
	if not exists(select 1 from sys_procs_states where mol_id = @mol_id and proc_name = @proc_name)
	begin
		insert into sys_procs_states(mol_id, proc_name) select @mol_id, @proc_name
	end
	declare @state_id int; select @state_id = id from sys_procs_states where mol_id = @mol_id and proc_name = @proc_name
	update sys_procs_states set canceled = 0, date_end = null where id = @state_id
		
-- цикл расчёта
	declare @alldates table(d_doc datetime primary key, processed bit)
	declare @dates table(d_doc datetime primary key, d_next datetime, output_q decimal, limit_q decimal, overlimit_q decimal)
	declare @d_doc datetime = isnull(@d_from,0), @d_next datetime
	
	-- начальные значения
	insert into @dates(d_doc, output_q, limit_q, overlimit_q) exec project_resources_overlimits @tree_id = @tree_id, @resource_id = @resource_id, @d_doc = @d_doc
	insert into @alldates(d_doc) select d_doc from @dates

	set @d_doc = (select top 1 d_doc from @dates)
	set @d_next = (select top 1 d_doc from @dates where d_doc > @d_doc)
	declare @i int = 0,	@canceled bit = 0

	-- цикл
	while @d_doc is not null and @i < 1000 and @canceled = 0
	begin
		select @canceled = canceled from sys_procs_states where id = @state_id

		if @d_doc is not null and @canceled = 0
		begin
			-- calc
			;exec project_resources_align @mol_id = @mol_id, @tree_id = @tree_id, @resource_id = @resource_id, @d_doc = @d_doc, @d_next = @d_next
			-- processed
			update @alldates set processed = 1 where d_doc = @d_doc
			-- state
			update x set 
				progress = 1.0 * (select count(*) from @alldates where processed = 1) / (select count(*) from @alldates)
			from sys_procs_states x with(nolock)
			where id = @state_id
		end

		-- следующая итерация
		delete from @dates
		insert into @dates(d_doc, output_q, limit_q, overlimit_q) exec project_resources_overlimits @tree_id = @tree_id, @resource_id = @resource_id, @d_doc = @d_doc
		insert into @alldates(d_doc) select d_doc from @dates where d_doc not in (select d_doc from @alldates) -- appends if any
	
		set @d_doc = (select top 1 d_doc from @dates where d_doc > @d_doc)
		set @d_next = (select top 1 d_doc from @dates where d_doc > @d_doc)

		set @i = @i + 1
	end	

	-- complete
	update sys_procs_states set date_end = getdate() where id = @state_id
end
go
