if object_id('project_resources_alignall_async') is not null drop proc project_resources_alignall_async
go
create proc [project_resources_alignall_async]
as
begin

	set nocount on;

	declare @xml xml, @h uniqueidentifier
	
	waitfor (
		receive @xml = message_body, @h = [conversation_handle] from [ResourcesAlignAllQueue]
	);

	begin try
		declare 
			@mol_id int = @xml.value('/mol_id[1]', 'int'),
			@tree_id int = @xml.value('/tree_id[1]', 'int'),
			@resource_id int = @xml.value('/resource_id[1]', 'int'),
			@d_from datetime = @xml.value('/d_from[1]', 'datetime')
			
		exec project_resources_alignall @mol_id = @mol_id, @tree_id = @tree_id, @resource_id = @resource_id, @d_from = @d_from
		end conversation @h		
	end try
	begin catch
		
		declare @err varchar(max) set @err = error_message()
		raiserror (@err, 16, 1)
		
	end catch

end
GO
