if object_id('document_delete') is not null 	drop procedure document_delete
go
create procedure document_delete
	@mol_id int,
	@document_id int,
	@deleted bit
AS  
begin  

	declare @document hierarchyid = (select node from documents where document_id = @document_id)

	if exists(
		select 1
		from documents
		where document_id = @document_id
			and name in ('Общие документы', 'Документы контрагентов', 'Проектные документы', 'Документы товарных позиций')
		)
	begin
		raiserror('Системные документы удалить невозможно.', 16, 1)
		return
	end

	if @deleted = 1
	begin
		declare @counts int = (
			select count(*) from documents where is_deleted = 0 and has_childs = 0
				and node.IsDescendantOf(@document) = 1
			)
		if @counts >= 10 begin
			raiserror('Данная папка содержит более 10 документов (всего: %d). Пакетное удаление большого числа документов невозможно.', 16, 1, @counts)
			return
		end
	end

	-- update document and all childs
	update documents set 
		is_deleted = @deleted,
		update_mol_id = @mol_id,
		update_date = getdate()
	where node.IsDescendantOf(@document) = 1
end
go
