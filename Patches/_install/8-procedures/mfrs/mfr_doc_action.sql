if object_id('mfr_doc_action') is not null drop proc mfr_doc_action
go
create proc mfr_doc_action
	@doc_id int,	
	@action varchar(50),
	@product_id int = null
as
begin

	set nocount on;

	if @action = 'AddMilestones'
	begin

		declare @subject_id int = (select subject_id from sdocs where doc_id = @doc_id)
		declare @last_doc_id int = (
			select max(ms.doc_id) from sdocs_mfr_milestones ms
				join sdocs sd on sd.doc_id = ms.doc_id and subject_id = @subject_id
			)

		insert into sdocs_mfr_milestones(
			doc_id, product_id, attr_id, ratio, ratio_value
		)
		select @doc_id, @product_id, attr_id, ratio, ratio_value
		from sdocs_mfr_milestones
		where doc_id = @last_doc_id

	end

end
go
