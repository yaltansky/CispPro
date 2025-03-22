if object_id('get_nds_account_id') is not null	drop proc get_nds_account_id
go
create proc get_nds_account_id
	@subject_id int,
	@account_id int out
as begin

	declare @vat_refund varchar(50) = dbo.app_registry_varchar('VATRefundAccountName')
	declare @nds_account_id int = (select account_id from findocs_accounts where subject_id = @subject_id and name = @vat_refund)

	if @nds_account_id is null begin
		insert into findocs_accounts(subject_id, name, number, ccy_id) values(@subject_id, @vat_refund, '#', 'RUR')
		set @nds_account_id = @@identity
	end
	
	set @account_id = @nds_account_id
end
GO
