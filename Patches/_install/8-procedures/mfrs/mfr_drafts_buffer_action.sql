if object_id('mfr_drafts_buffer_action') is not null drop proc mfr_drafts_buffer_action
go
-- exec mfr_drafts_buffer_action 1000, 'AddAttrs'
create proc mfr_drafts_buffer_action
	@mol_id int,
	@action varchar(32),
	@option_version varchar(30) = null
as
begin

    set nocount on;

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfd')

    BEGIN TRY
        if @action in ('CheckAccessAdmin', 'CheckAccess')
        begin
            if (
                select count(distinct sd.subject_id) 
                from sdocs_mfr_contents c
                    join sdocs sd on sd.doc_id = c.mfr_doc_id
                where draft_id in (select id from @buffer)
                ) > 1
            begin
                raiserror('Элементы состава изделия должны быть из одного субъекта учёта.', 16, 1)
                return
            end

            declare @subject_id int = (
                select top 1 sd.subject_id
                from sdocs_mfr_contents c
                    join sdocs sd on sd.doc_id = c.mfr_doc_id
                where draft_id in (select id from @buffer)
                )
        
            if dbo.isinrole_byobjs(@mol_id, 
                case when @action = 'CheckAccessAdmin' then 'Mfr.Admin' else 'Mfr.Moderator' end,
                'SBJ', @subject_id) = 0
            begin
                raiserror('У Вас нет доступа к модерации объектов в данном субъекте учёта.', 16, 1)
                return
            end
        end

        else if @action = 'AddAttrs' 
        begin
            exec mfr_drafts_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

            delete x from sdocs_mfr_drafts_attrs x
                join @buffer buf on buf.id = x.draft_id
                join sdocs_mfr_drafts_attrs attr on attr.draft_id = -@mol_id and attr.attr_id = x.attr_id
                
            insert into sdocs_mfr_drafts_attrs(draft_id, attr_id, note, add_mol_id)
            select distinct x.draft_id, attr.attr_id, attr.note, @mol_id
            from sdocs_mfr_drafts x
                join @buffer buf on buf.id = x.draft_id
                join sdocs_mfr_drafts_attrs attr on attr.draft_id = -@mol_id
        end

        else if @action = 'RemoveAttrs' 
        begin
            exec mfr_drafts_buffer_action @mol_id = @mol_id, @action = 'CheckAccess'

            delete x
            from sdocs_mfr_drafts_attrs x
                join @buffer buf on buf.id = x.draft_id
                join sdocs_mfr_drafts_attrs attr on attr.draft_id = -@mol_id and attr.attr_id = x.attr_id
        end

        else if @action = 'SpreadDrafts'
        begin		
            exec mfr_drafts_buffer_action @mol_id = @mol_id, @action = 'CheckAccessAdmin'
            create table #docs(id int primary key)
            insert into #docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id between 0 and 99
            
            create table #drafts_map(source_id int index ix_source, target_id int index ix_target)

                insert into #drafts_map(source_id, target_id)
                select distinct x.draft_id, x2.draft_id
                from mfr_drafts x
                    join @buffer b on b.id = x.draft_id
                    join mfr_drafts x2 on x2.item_id = x.item_id
                        join #docs i on i.id = x2.mfr_doc_id
                where x.is_buy = 0
                    and x.is_deleted = 0
                    and x2.draft_id != x.draft_id
                    and x2.is_buy = 0
                    and x2.status_id != 100
                    and x2.is_deleted = 0

                -- check on empty
                if not exists(select 1 from #drafts_map)
                begin
                    raiserror('Не удалось сформировать перечень тех.выписок для тиражирвоания.', 16, 1)
                    return
                end	
    
                BEGIN TRY
                BEGIN TRANSACTION
                    delete from mfr_drafts_opers where draft_id in (select target_id from #drafts_map)

                    declare @map as app_mapids; insert into @map(new_id, id) select source_id, target_id from #drafts_map
                    exec mfr_draft_sync;2 @mol_id = @mol_id, @map_reversed = @map, @parts = 'opers'

                    update x set 
                        status_id = xs.status_id, 
                        executor_id = xs.executor_id,
                        update_mol_id = @mol_id,
                        update_date = getdate()
                    from mfr_drafts x
                        join #drafts_map m on m.target_id = x.draft_id
                            join mfr_drafts xs on xs.draft_id = m.source_id

                COMMIT TRANSACTION
                END TRY

                BEGIN CATCH
                    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
                    declare @err varchar(max) = error_message()
                    raiserror (@err, 16, 3)
                END CATCH -- TRANSACTION

                -- пересчёт состава изделия (через очередь)
                    -- add docs
                    insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                    select distinct @buffer_id, 'mfr', mfr_doc_id, 0 from mfr_drafts
                        where draft_id in (select target_id from #drafts_map)
                    -- queue mfr_drafts_calc
                    declare @q uniqueidentifier = newid()
                    declare @sql_cmd nvarchar(max) = concat('exec mfr_drafts_calc @mol_id = 0, @queue_id = ''', @q, '''')
                    exec queue_append @queue_id = @q, @mol_id = @mol_id, @priority = 0, @use_buffer = 1,
                        @thread_id = 'mfrs',
                        @name = 'Пересчёт состава изделия',
                        @sql_cmd = @sql_cmd

                -- поместить задействованные техвыписки в буфер
                exec objs_buffer_clear @mol_id, 'mfd'
                insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
                select @buffer_id, 'mfd', target_id, 0 from #drafts_map

            exec drop_temp_table '#docs,#drafts_map'
        end

        else if @action = 'ExportToPdm'
            exec mfr_drafts_to_pdm @mol_id = @mol_id, @option_version = @option_version, @drafts = @buffer

    END TRY
    BEGIN CATCH
        declare @errtry varchar(max) = error_message()
        raiserror (@errtry, 16, 3)
    END CATCH -- TRY

end
go
