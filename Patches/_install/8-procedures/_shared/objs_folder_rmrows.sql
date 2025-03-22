if object_id('objs_folder_rmrows') is not null drop proc objs_folder_rmrows
go
create proc objs_folder_rmrows
	@mol_id int,
	@folder_id int,
	@obj_type varchar(20),
	@obj_ids varchar(max)
as
begin
	
    if @obj_ids is null begin
        declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
        delete x from objs_folders_details x
            join objs_folders_details xx on xx.folder_id = @buffer_id and xx.obj_type = x.obj_type and xx.obj_id = x.obj_id
        where x.folder_id = @folder_id and x.obj_type = @obj_type
    end

    else begin
        declare @ids app_pkids

        insert into @ids select distinct item
        from dbo.str2rows(@obj_ids, ',')
        where try_cast(item as int) is not null

        delete x from objs_folders_details x
            join @ids i on i.id = x.obj_id
        where folder_id = @folder_id and obj_type = @obj_type
    end
end
GO
