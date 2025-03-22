if object_id('mfr_items_buffer_action') is not null drop proc mfr_items_buffer_action
go
-- exec mfr_items_buffer_action 1000, 'CreateJobsInfo'
-- exec mfr_items_buffer_action 1000, 'AddAttrs'
-- exec mfr_items_buffer_action 1000, 'AppendMaterials'
create proc mfr_items_buffer_action
	@mol_id int,
	@action varchar(32),
	@place_id int = null,
	@d_from datetime = null,
	@d_to datetime = null,
	@context varchar(20) = null, -- 'plan', 'doc'	
	@queue_id uniqueidentifier = null
as
begin

    set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
        declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 'action = ', @action)
        exec tracer_log @tid, @tid_msg      

	declare @today datetime = dbo.today()
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfc')

	declare @contents table(content_id int primary key, item_id int, context_id varchar(24))

	BEGIN TRY
	BEGIN TRANSACTION

		if @action = 'AddAttrs' 
		begin
			exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'

			insert into @contents
			exec mfr_items_buffer_action;2 @buffer = @buffer, @context = @context

			-- update contents
			delete x from sdocs_mfr_drafts_attrs x
				join sdocs_mfr_contents c on c.draft_id = x.draft_id
					join @contents ic on ic.content_id = c.content_id
				join sdocs_mfr_drafts_attrs attr on attr.draft_id = -@mol_id and attr.attr_id = x.attr_id
				
			insert into sdocs_mfr_drafts_attrs(draft_id, attr_id, note, add_mol_id)
			select distinct c.draft_id, attr.attr_id, attr.note, @mol_id
			from sdocs_mfr_contents c
				join @contents ic on ic.content_id = c.content_id
				join sdocs_mfr_drafts_attrs attr on attr.draft_id = -@mol_id
		end

		else if @action = 'RemoveAttrs' 
		begin
			exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'

			insert into @contents
			exec mfr_items_buffer_action;2 @buffer = @buffer, @context = @context

			delete x
			from sdocs_mfr_drafts_attrs x
				join sdocs_mfr_contents c on c.draft_id = x.draft_id
					join @buffer buf on buf.id = c.content_id
				join sdocs_mfr_drafts_attrs attr on attr.draft_id = -@mol_id and attr.attr_id = x.attr_id
		end

		else if @action = 'ToggleBuy' 
		begin
			exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'

			update mfr_drafts set is_buy = is_buy ^ 1
			where draft_id in (
					select draft_id from sdocs_mfr_contents c
						join queues_objs objs on queue_id = @queue_id and obj_type = 'mfc' and obj_id = c.content_id
					)
			
			declare @docs app_pkids
				insert into @docs
				select distinct c.mfr_doc_id from sdocs_mfr_contents c
					join queues_objs objs on queue_id = @queue_id and obj_type = 'mfc' and obj_id = c.content_id
				
			exec mfr_drafts_calc @mol_id = @mol_id, @docs = @docs
		end

		else if @action = 'CalcItemsRegister'
		begin
			exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'

			declare @items as app_pkids; insert into @items select distinct item_id from sdocs_mfr_contents
				join @buffer i on i.id = content_id
			exec mfr_plan_jobs_calc @mol_id = @mol_id, @items = @items, @queue_id = @queue_id
		end

		else if @action = 'CompareOpersWithPdm'
		begin
			create table #iba_contents(
				content_id int, 
				pdm_id int index ix_pdm,
				pdm_variant_number int,
				c_opers int
				)
			create table #iba_opers(
				content_id int, pdm_id int, pdm_variant_number int,
				oper_id int, place_id int, number int, name varchar(50),
				checked bit,
				primary key (pdm_variant_number, oper_id)
				)

			insert into #iba_contents(content_id, pdm_id, pdm_variant_number, c_opers)
			select c.content_id, p.pdm_id, p.variant_number, c.c_opers
			from (
				select c.content_id, c.item_id, c.draft_id, c_opers = count(*)
				from sdocs_mfr_opers o
					join sdocs_mfr_contents c on c.content_id = o.content_id
						join @buffer i on i.id = c.content_id
				group by c.content_id, c.item_id, c.draft_id
				) c
				join (
					select p.pdm_id, p.item_id, o.variant_number, c_opers = count(*)
					from mfr_pdm_opers o
						join mfr_pdms p on p.pdm_id = o.pdm_id
					group by p.pdm_id, p.item_id, o.variant_number
				) p on p.item_id = c.item_id and p.c_opers = c.c_opers

			insert into #iba_opers(content_id, pdm_id, pdm_variant_number, oper_id, place_id, number, name)
			select c.content_id, c.pdm_id, c.pdm_variant_number, o.oper_id, o.place_id, o.number, o.name
			from sdocs_mfr_opers o
				join #iba_contents c on c.content_id = o.content_id

			-- удалить то, что соответствует
			delete xc from #iba_contents xc
				join (
					select x.content_id
					from #iba_opers x
						join #iba_contents c on c.content_id = x.content_id and c.pdm_variant_number = x.pdm_variant_number
						join mfr_pdm_opers o on o.pdm_id = x.pdm_id and o.variant_number = x.pdm_variant_number
							and o.place_id = x.place_id and o.number = x.number and o.name = x.name
					group by x.content_id, x.pdm_variant_number, c.c_opers
					having count(*) = c.c_opers
				) xo on xo.content_id = xc.content_id
			
			-- оставшееся - это несоответствия --> поместить в буфер
			exec objs_buffer_clear @mol_id, 'mfc'
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select distinct @buffer_id, 'mfc', content_id, 0 from #iba_contents

			exec drop_temp_table '#iba_contents,#iba_opers'
		end

	COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH -- TRANSACTION

    -- trace end
        exec tracer_close @tid
end
go
-- helper: create @contents by @context
create proc mfr_items_buffer_action;2
	@buffer as app_pkids readonly,
	@context varchar(20) = null -- 'plan', 'doc'
as
begin

	declare @contents table(content_id int primary key, item_id int, context_id varchar(24))

	if @context is not null
	begin
		declare @plan_id int, @mfr_doc_id int
		select top 1
			@plan_id = plan_id,
			@mfr_doc_id = mfr_doc_id
		from sdocs_mfr_contents c
			join @buffer buf on buf.id = c.content_id

		-- @contents depends on @context
		insert into @contents(content_id, item_id, context_id)
		select c.content_id, c.item_id,
			concat(
				substring(@context, 1, 1),
				case
					when @context = 'plan' then c.plan_id
					when @context = 'doc' then c.mfr_doc_id
				end
				)
		from sdocs_mfr_contents c
			join (
				select distinct item_id from sdocs_mfr_contents
				where content_id in (select id from @buffer)
			) i on i.item_id = c.item_id
		where (@context = 'doc' and c.mfr_doc_id = @mfr_doc_id)
			or (@context = 'plan' and c.plan_id = @plan_id)
	end

	else
		insert into @contents(content_id, item_id)
		select c.content_id, c.item_id
		from sdocs_mfr_contents c 
			join @buffer buf on buf.id = c.CONTENT_ID

	select content_id, item_id, context_id from @contents
end
go
