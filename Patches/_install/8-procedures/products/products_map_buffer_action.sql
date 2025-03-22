if object_id('products_map_buffer_action') is not null drop proc products_map_buffer_action
go
create proc products_map_buffer_action
	@mol_id int,
	@action varchar(32),
    @pattern varchar(500) = null,
    @unit_id int = null
as
begin
    set nocount on;

    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
    -- params
        declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
        declare @buffer as app_pkids
        insert into @buffer select id from dbo.objs_buffer(@mol_id, 'PMAP')

    BEGIN TRY
    BEGIN TRANSACTION

        if @action in ('AddNewProducts')
        begin
            exec products_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'
            
            -- add news
            declare @map table(map_id int, product_id int index ix_product)
            
            insert into products(extern_id, name, unit_id, status_id, add_date, mol_id)
                output inserted.extern_id, inserted.product_id into @map
            select x.id, x.name, @unit_id, 0, getdate(), @mol_id
            from products_maps x
                join @buffer i on i.id = x.id
            where x.product_id is null

            -- use pattern
            update x set name = replace(replace(@pattern, 
                                '@ID', x.product_id),
                                '@NAME', name)
            from products x
                join @map m on m.product_id = x.PRODUCT_ID

            -- update maps
            update x set product_id = m.product_id
            from products_maps x
                join @map m on m.map_id = x.id

            -- add to buffer
            exec objs_buffer_clear @mol_id, 'P'
            insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
            select @buffer_id, 'P', product_id, 0
            from @map
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
