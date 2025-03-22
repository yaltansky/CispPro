if object_id('mfr_items_sign') is not null drop proc mfr_items_sign
go
create proc mfr_items_sign
	@mol_id int,
	@task_id int,
	@action_id varchar(32)
as
begin

	set nocount on;	

	declare @refkey varchar(250) = (select refkey from tasks where task_id = @task_id)
	declare @content_id int = dbo.strtoken(@refkey, '/', 6)
	update sdocs_mfr_contents set last_task_id = @task_id where content_id = @content_id

end
go
