if object_id('deals_bind') is not null drop proc deals_bind
go
create proc deals_bind
	@mol_id int,
	@status_id int = null
as
begin

    set nocount on;

	declare @deals table(deal_id int primary key, subject_id int)

		insert into @deals(deal_id, subject_id)
		select deal_id, subject_id
		from deals
		where deal_id in (select id from dbo.objs_buffer(@mol_id, 'dl'))

	if (	select count(distinct subject_id) from @deals) > 1
	begin
		raiserror('Сделки должны быть из одного субъекта учёта.', 16, 1)
		return
	end

	declare @subject_id int = (select top 1 subject_id from @deals)
	
	if dbo.isinrole_byobjs(@mol_id, 'Admin,Finance.Budgets.Admin,Finance.Budgets.Operator', 'SBJ', @subject_id) = 0
	begin
		raiserror('У Вас нет доступа к модерации объектов в данном субъекте учёта.', 16, 1)
		return
	end

	update deals
	set status_id = @status_id, update_date = getdate(), update_mol_id = @mol_id
	where deal_id in (select id from dbo.objs_buffer(@mol_id, 'dl'))
end
go
