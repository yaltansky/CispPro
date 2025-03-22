if object_id('mfr_pdm_buffer_action') is not null drop proc mfr_pdm_buffer_action
go
-- exec mfr_pdm_buffer_action 700, 'AddAttrs'
create proc mfr_pdm_buffer_action
	@mol_id int,
	@action varchar(32)
as
begin

    set nocount on;

	declare @buffer_id int = dbo.objs_buffer_id(@mol_id)
	declare @buffer as app_pkids; insert into @buffer select id from dbo.objs_buffer(@mol_id, 'mfpdm')

end
go
