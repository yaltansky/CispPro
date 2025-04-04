if object_id('mfr_pdm_buffer_action') is not null drop proc mfr_pdm_buffer_action
go
-- exec mfr_pdm_buffer_action 700, 'AddAttrs'
create proc mfr_pdm_buffer_action
	@mol_id int,
	@action varchar(32),
    @context varchar(max) = null,
    @old_item_id int = null,
    @new_item_id int = null
as
begin

    set nocount on;
    
    declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfpdm')

    if @action = 'ChangeMaterial' 
    begin
        declare @rowscount int = (select count(*) from mfr_pdm_items x join @buffer i on i.id = x.pdm_id where x.item_id = @old_item_id)
        if @rowscount = 0
        begin
            raiserror('Заменяемый материал отсутствует в выбранных карточках ДСЕ.', 16, 1)
            return
        end    

        update x set item_id = @new_item_id
        from mfr_pdm_items x
            join @buffer i on i.id = x.pdm_id
        where x.item_id = @old_item_id
        
    end
end
go
