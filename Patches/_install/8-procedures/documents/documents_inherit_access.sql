if object_id('documents_inherit_access') is not null
	drop proc documents_inherit_access
go

create proc documents_inherit_access
	@document_id int
as
begin
	set nocount on;

	declare @document hierarchyid = (select node from documents where document_id = @document_id)
	
	update x
	set inherited_access = 1
	from documents x
	where x.node.IsDescendantOf(@document) = 1
		and x.document_id <> @document_id

end
GO
