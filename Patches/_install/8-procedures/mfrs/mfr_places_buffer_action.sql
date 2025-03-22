if object_id('mfr_places_buffer_action') is not null drop proc mfr_places_buffer_action
go
create proc mfr_places_buffer_action
	@mol_id int,
	@action varchar(32),
	@d_doc datetime = null
as
begin

    set nocount on;

	declare @proc_name varchar(50) = object_name(@@procid)
	exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @action = 'Any'
    if @@error != 0 return
	
	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfl')
	declare @wksheets table(wk_sheet_id int primary key, place_id int)

	if @action = 'createWksheets'
	begin
		set @d_doc = isnull(@d_doc, dbo.today())

		-- create wksheets
			insert into mfr_wk_sheets(subject_id, place_id, d_doc, status_id, add_mol_id)
				output inserted.wk_sheet_id, inserted.place_id into @wksheets
			select distinct pl.subject_id, pl.place_id, @d_doc, 0, @mol_id
			from mfr_places pl
				join @buffer i on i.id = pl.place_id
				
		-- append to buffer
			delete from objs_folders_details where folder_id = @buffer_id and obj_type = 'mfw'
			insert into objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
			select @buffer_id, 'mfw', wk_sheet_id, @mol_id
			from @wksheets

		-- adjust auto-numbers
			update x
			set number = concat(s.short_name, '/ТАБ-', x.wk_sheet_id)
			from mfr_wk_sheets x
				join @wksheets j on j.wk_sheet_id = x.wk_sheet_id
					join subjects s on s.subject_id = x.subject_id

		-- add details
			declare @wk_sheet_id int, @place_id int
			declare c_wksheets cursor local read_only for select wk_sheet_id, place_id from @wksheets

			open c_wksheets; fetch next from c_wksheets into @wk_sheet_id, @place_id
			BEGIN TRY
				while (@@fetch_status != -1)
				begin
					if (@@fetch_status != -2) 
					begin
						exec mfr_wk_sheet_addmols @mol_id = @mol_id, @wk_sheet_id = @wk_sheet_id, @place_id = @place_id
					end
					fetch next from c_wksheets into @wk_sheet_id, @place_id
				end
			END TRY

			BEGIN CATCH
				declare @err varchar(max) = error_message()
				raiserror (@err, 16, 1)
			END CATCH

			close c_wksheets; deallocate c_wksheets
	end
end
go
