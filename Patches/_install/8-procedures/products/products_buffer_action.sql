if object_id('products_buffer_action') is not null drop proc products_buffer_action
go
create proc products_buffer_action
	@mol_id int,
	@action varchar(32),
	@status_id int = null,
	@plan_group_id int = null,
	@product_id int = null,
	@manager_id int = null,
	@store_keeper_id int = null
as
begin
    -- trace start
        declare @trace bit = isnull(cast((select dbo.app_registry_value('SqlProcTrace')) as bit), 0)
        declare @proc_name varchar(50) = object_name(@@procid)
        declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace
    -- params
        declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
        
        declare @buffer as app_pkids
            if @product_id is null or @action = 'CoalesceAttrs'
                insert into @buffer select id from dbo.objs_buffer(@mol_id, 'P')
            else 
                insert into @buffer select @product_id

        declare @attr_id int

    BEGIN TRY
    BEGIN TRANSACTION

        if @action in ('SaveAttrs', 'AddAttrs')
        begin
            exec products_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            delete x from products_attrs x
                join @buffer i on i.id = x.product_id
                join products_attrs attr on attr.product_id = -@mol_id and attr.attr_id = x.attr_id
                
            insert into products_attrs(product_id, attr_id, attr_value, add_mol_id)
            select distinct x.product_id, attr.attr_id, attr.attr_value, @mol_id
            from products x
                join @buffer i on i.id = x.product_id
                join products_attrs attr on attr.product_id = -@mol_id
            where attr.is_deleted = 0
        end

        else if @action = 'RemoveAttrs' 
        begin
            exec products_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'any'

            delete x from products_attrs x
                join @buffer i on i.id = x.product_id
                join products_attrs attr on attr.product_id = -@mol_id and attr.attr_id = x.attr_id
        end

        else if @status_id is not null
        begin
            exec products_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'admin'

            update x set status_id = @status_id, update_mol_id = @mol_id , update_date = getdate()
            from products x
                join @buffer i on i.id = x.product_id
        end

        else if @plan_group_id is not null
        begin
            exec products_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'any'

            update x set plan_group_id = @plan_group_id, update_mol_id = @mol_id, update_date = getdate()
            from products x
                join @buffer i on i.id = x.product_id
        end

        else if @manager_id is not null
        begin
            exec products_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'any'

            set @attr_id = (select top 1 attr_id from prodmeta_attrs where code = 'закупка.КодМенеджера')
            
            delete x from products_attrs x
                join @buffer i on i.id = x.product_id and x.attr_id = @attr_id

            -- update dictionary
            insert into products_attrs(product_id, attr_id, attr_value_id)
            select id, @attr_id, mols.mol_id
            from @buffer i
                join mols on mols.mol_id = @manager_id

            -- sync refs
            update c set manager_id = pa.attr_value_id
            from sdocs_mfr_contents c
                join products_attrs pa on pa.product_id = c.item_id and attr_id = @attr_id
            where isnull(c.manager_id,0) != pa.attr_value_id

        end

        else if @store_keeper_id is not null
        begin
            exec products_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'any'

            set @attr_id = (select top 1 attr_id from prodmeta_attrs where code = 'закупка.КодКладовщика')
            
            delete x from products_attrs x
                join @buffer i on i.id = x.product_id and x.attr_id = @attr_id

            insert into products_attrs(product_id, attr_id, attr_value_id)
            select id, @attr_id, mols.mol_id
            from @buffer i
                join mols on mols.mol_id = @store_keeper_id
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
