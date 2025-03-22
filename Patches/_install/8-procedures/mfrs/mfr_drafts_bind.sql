if object_id('mfr_drafts_bind') is not null drop proc mfr_drafts_bind
go
create proc mfr_drafts_bind
	@mol_id int,
	@draft_id int = null,
	@status_id int = null, -- установить статус деталей производстенного плана (в буфере)
	@route_id int = null, -- привязать операции (маршрут @route_id) к деталям производстенного плана (в буфере)
	@executor_id int = null, -- исполнитель
	@pdm_id int = null, -- карточка ДСЕ + настройки
	@pdm_selection xml = null
as
begin

    set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
        declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
            'status_id = ', @status_id,
            'route_id = ', @route_id,
            'executor_id = ', @executor_id,
            'pdm_id = ', @pdm_id
            )
        exec tracer_log @tid, @tid_msg      

    BEGIN TRY
        if @status_id is not null
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'

            update mfr_drafts
            set status_id = @status_id,
                context = case when mfr_doc_id > 0 and @status_id = 100 then 'protected' else context end,
                update_mol_id = @mol_id,
                update_date = getdate()
            where draft_id in (select id from dbo.objs_buffer(@mol_id, 'mfd'))
        end

        if @pdm_id is not null 
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'

            set @draft_id = isnull(@draft_id, (
                select top 1 x.draft_id
                from mfr_drafts x
                    join dbo.objs_buffer(@mol_id, 'mfd') i on i.id = x.draft_id
                ))

            delete from mfr_drafts_pdm where draft_id = @draft_id

            declare @hxml int; exec sp_xml_preparedocument @hxml output, @pdm_selection

                declare @route_number int = isnull(
                    (select top 1 RouteNumber from openxml(@hxml, '/*/RouteNumber', 2) with (RouteNumber int 'text()'))
                    , 1)
                    -- validate
                    if not exists(select 1 from mfr_pdm_opers where pdm_id = @pdm_id and variant_number = @route_number)
                        set @route_number = (select min(variant_number) from mfr_pdm_opers where pdm_id = @pdm_id)
                    
                -- base info
                insert into mfr_drafts_pdm(draft_id, pdm_id, route_number, add_mol_id)
                select @draft_id, @pdm_id, @route_number, @mol_id
                -- options
                insert into mfr_drafts_pdm(draft_id, pdm_id, pdm_option_id, add_mol_id)
                select @draft_id, @pdm_id, pdm_option_id, @mol_id from openxml(@hxml, '/*/Options/*', 2) with (pdm_option_id int 'text()')
                where pdm_option_id is not null
                -- analogs
                insert into mfr_drafts_pdm(draft_id, pdm_id, analog_id, add_mol_id)
                select @draft_id, @pdm_id, it.id, @mol_id 
                from openxml(@hxml, '/*/Analogs/*', 2) with (id int 'text()') x
                    join mfr_pdm_items it on it.id = x.id
                    
                    -- check defaults (if not selected)
                    declare c_analogs cursor local read_only for 
                        select analog_id = id from mfr_pdm_items where pdm_id = @pdm_id and has_childs = 1
                    
                    declare @analog_id int
                    
                    open c_analogs; fetch next from c_analogs into @analog_id
                        while (@@fetch_status != -1)
                        begin
                            if not exists(
                                select 1 from mfr_drafts_pdm where draft_id = @draft_id 
                                    and analog_id in (select id from mfr_pdm_items where pdm_id = @pdm_id and parent_id = @analog_id)
                                )
                                insert into mfr_drafts_pdm(draft_id, pdm_id, analog_id, add_mol_id)
                                select @draft_id, @pdm_id, @analog_id, @mol_id 
                            fetch next from c_analogs into @analog_id
                        end
                    close c_analogs; deallocate c_analogs

            exec sp_xml_removedocument @hxml

            update mfr_drafts set pdm_id = @pdm_id, update_mol_id = @mol_id, update_date = getdate()
            where draft_id = @draft_id

            exec mfr_drafts_from_pdm @mol_id = @mol_id, @start_draft_id = @draft_id
        end

        if @route_id is not null 
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'

            declare @plan_id int = (select top 1 plan_id from sdocs_mfr_contents where content_id in (select id from dbo.objs_buffer(@mol_id, 'mfc')))
            
            -- @contents
                declare @contents as app_pkids
                insert into @contents select content_id from sdocs_mfr_contents 
                where plan_id = @plan_id and 
                    item_id in (
                        select item_id from sdocs_mfr_contents 
                        where content_id in (select id from dbo.objs_buffer(@mol_id, 'mfc'))
                        )

            -- @drafs		
                declare @drafs as app_pkids; insert into @drafs select id from dbo.objs_buffer(@mol_id, 'mfd')

            -- update opers (of drafts)
                delete x from mfr_drafts_opers x where x.draft_id in (select id from @drafs)
                
                insert into mfr_drafts_opers(
                    draft_id,
                    place_id, work_type_id, type_id, name, number,
                    duration, duration_id, duration_wk, duration_wk_id,
                    add_mol_id
                    )
                select
                    i.id,
                    x.place_id,
                    2, -- закупка
                    x.type_id, x.name, x.number,
                    x.duration, x.duration_id, x.duration, x.duration_id,
                    @mol_id
                from @drafs i
                    join mfr_routes_details x on x.route_id = @route_id
        end

        if @executor_id is not null
        begin
            exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'BindExecutor'

            declare @tasks table (
                task_id int index ix_task,
                draft_id int,
                refkey varchar(255) index ix_refkey
                )
                insert into @tasks(draft_id, refkey)
                select x.draft_id, concat('/mfrs/docs/', x.mfr_doc_id, '/drafts/', x.draft_id)
                from mfr_drafts x
                    join dbo.objs_buffer(@mol_id, 'mfd') i on i.id = x.draft_id

                update x set task_id = t.task_id
                from @tasks x
                    join (
                        select refkey, max(task_id) as task_id
                        from tasks 
                        where refkey like '/mfrs/docs%'
                        group by refkey
                    ) t on t.refkey = x.refkey

            declare @tasks_added table (task_id int primary key, draft_id int)

            insert into tasks(type_id, author_id, analyzer_id, title, status_id, refkey, parent_id)
                output inserted.task_id, inserted.parent_id into @tasks_added
            select top 50
                1, @mol_id, @mol_id,
                concat('Чертёжная деталь #', draft_id),
                0,
                refkey,
                draft_id
            from @tasks
            where task_id is null
            
            update x set task_id = a.task_id
            from @tasks x
                join @tasks_added a on a.draft_id = x.draft_id

            -- status_id
            update x set status_id = 0, author_id = @mol_id
            from tasks x
                join @tasks xx on xx.task_id = x.task_id

            -- delete old executors
            delete x from tasks_mols x
                join @tasks xx on xx.task_id = x.task_id
            where x.role_id = 1

            declare c_tasks cursor local read_only for select task_id, draft_id from @tasks
            declare @task_id int

            open c_tasks; fetch next from c_tasks into @task_id, @draft_id
                begin try
                    while (@@fetch_status <> -1)
                    begin
                        if (@@fetch_status <> -2)
                        begin
                            declare @comment varchar(max) = concat('Прошу принять к исполнению работу над заполнением разделов по чертёжной детали #', @draft_id, '.')

                            exec task_sign @task_id = @task_id,
                                @action_id = 'Assign',
                                @action_name = 'К исполнению',
                                @from_mol_id = @mol_id,
                                @to_mols_ids = @executor_id,
                                @comment = @comment,
                                @body = @comment

                            update tasks set parent_id = null where task_id = @task_id
                        end
                        fetch next from c_tasks into @task_id, @draft_id
                    end
                end try 
                begin catch end catch
            close c_tasks; deallocate c_tasks
        end
    END TRY
    BEGIN CATCH
        declare @errtry varchar(max) = error_message()
        raiserror (@errtry, 16, 3)
    END CATCH
end
go
