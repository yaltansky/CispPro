if object_id('documents_checkaccess') is not null
	drop proc documents_checkaccess
go
/** 
    declare @allowaccess bit
    exec documents_checkaccess 307, 45113, 'update', @allowaccess = @allowaccess out
    select @allowaccess
**/
create proc documents_checkaccess
	@mol_id int,
	@document_id int,
	@accesstype varchar(16) = 'update', -- read | update
	@allowaccess bit out
as
begin

	set @allowaccess = 0
    
	if dbo.isinrole(@mol_id, 'Projects.Admin,Documents.Admin') = 1
	begin
		set @allowaccess = 1
	end

	else
	begin

		if exists(
			select 1 from documents where document_id = @document_id 
			and @mol_id in (mol_id, response_id)
			)
		begin
			set @allowaccess = 1
		end
				
		else begin

			declare @project_id int
			declare @access varchar(10)
			
			exec document_get_owner @document_id = @document_id, @owner_id = @project_id out, @owner_key = null

			if @accesstype = 'update'
			begin
				if @project_id is not null
				begin
					-- Проверяем супер-права
					if dbo.isinrole(@mol_id, 'Projects.Admin') = 1
					begin
						set @allowaccess = 1
					end

					if @allowaccess = 0
					begin
                        exec project_section_getaccess @mol_id = @mol_id, @project_id = @project_id, @section = 'documents', @access = @access out

						set @allowaccess = 
                            case
                                when charindex('U', @access) > 0
                                    or exists(select 1 from documents_mols where document_id = @document_id and @mol_id = mol_id and a_update = 1)
                                then 1
                                else 0
                            end
					end
				end
			end

			else if @accesstype = 'read'
			begin
				declare @check_document_id int = (select ref_document_id from documents where document_id = @document_id)
				if @check_document_id is null set @check_document_id = @document_id

				set @allowaccess = 
						case
							when exists(select 1 from documents where document_id = @check_document_id and account_level_id is null)
								or exists(select 1 from documents_mols where document_id = @check_document_id and mol_id = @mol_id and a_read = 1) then 1
							else 0
						end
			end
		end
	end

end
GO
