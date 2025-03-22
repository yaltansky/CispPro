if object_id('mfr_swaps_apply') is not null drop proc mfr_swaps_apply
go
create proc mfr_swaps_apply
	@mol_id int,
	@queue_id uniqueidentifier = null
as
begin	
	set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid), @tid_msg varchar(max)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	-- #sw_swaps
		create table #sw_swaps(id int primary key)

		if @queue_id is not null
		begin
			insert into #sw_swaps select obj_id from queues_objs
			where queue_id = @queue_id and obj_type = 'swp'
		end
		else
			insert into #sw_swaps select id from dbo.objs_buffer(@mol_id, 'swp')

		set @tid_msg = concat('#sw_swaps: ', (select count(*) from #sw_swaps), ' rows')
		exec tracer_log @tid, @tid_msg

	-- change status_id
		update sdocs set status_id = 100, update_date = getdate(), executor_id = @mol_id
		where doc_id in (select id from #sw_swaps)

	-- @docs
		declare @docs app_pkids
		insert into @docs 
			select distinct mfr.doc_id
			from mfr_swaps swp
				join #sw_swaps i on i.id = swp.doc_id
				join mfr_swaps_products sp on sp.doc_id = swp.doc_id
					join mfr_sdocs mfr on mfr.number = sp.mfr_number

		set @tid_msg = concat('@docs: ', (select count(*) from @docs), ' rows')
		exec tracer_log @tid, @tid_msg

	-- calc drafts
		if exists(select 1 from @docs)
		begin
			exec mfr_drafts_calc @mol_id = @mol_id, @docs = @docs
			exec mfr_opers_calc @mol_id = @mol_id, @docs = @docs, @mode = 3
		end
end
go
