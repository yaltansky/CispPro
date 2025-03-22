if object_id('buyorder_sign') is not null drop proc buyorder_sign
go
create proc buyorder_sign
	@mol_id int,
	@doc_id int,
	@action_id varchar(32)
as
begin

	SET NOCOUNT ON;

	if @action_id in ('Send')
		update sdocs set status_id = 10
		where doc_id = @doc_id

	if @action_id in ('PassToAcceptance')
	begin
		update sdocs set status_id = 5
		where doc_id = @doc_id
	end

	if @action_id in ('Revoke')
	begin
		update sdocs set status_id = 0
		where doc_id = @doc_id
	end	

end
go
