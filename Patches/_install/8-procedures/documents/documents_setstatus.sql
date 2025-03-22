if object_id('documents_setstatus') is not null drop proc documents_setstatus
go
create proc documents_setstatus
-- documents must be in buffer
	@mol_id int,
	@buffer_id int,
	@status_id int
as
begin

	set nocount on;

	declare @is_admin bit = dbo.isinrole(@mol_id, 'Documents.Admin')

-- #docs
	create table #docs (document_id int primary key, node hierarchyid)

	insert into #docs(document_id, node) 
	select document_id, node from documents 
	where document_id in (
		select obj_id from objs_folders_details where folder_id = @buffer_id
		)

	insert into #docs(document_id)
	select d.document_id
	from documents d
		join #docs x on d.node.IsDescendantOf(x.node) = 1
	where d.document_id <> x.document_id

-- #results
	create table #results (document_id int primary key)
	if @is_admin = 1
		insert into #results select document_id from #docs
	else
		insert into #results select distinct d.document_id from #docs d
			join documents_mols dm on dm.document_id = d.document_id and dm.mol_id = @mol_id and dm.a_update = 1

-- action	
	update d
	set status_id = @status_id
	from documents d
		join #results x on x.document_id = d.document_id
	where d.has_childs = 0
end
GO
