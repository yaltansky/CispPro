if object_id('project_buys_sheet') is not null drop proc project_buys_sheet
go
create proc project_buys_sheet
	@project_id int,
	@search varchar(250)
as
begin

	set nocount on;

	select
		P.PRODUCT_ID,
		P.NAME AS PRODUCT_NAME,
		BS.QUANTITY,
		BS.Q_BUY,
		BS.Q_STOCK,
		BS.Q_MFS,
		BS.Q_LEFT
	from projects_buys_sheets bs
		join products p on p.product_id = bs.product_id
	where bs.project_id = @project_id
		and (@search is null or p.name like '%' + @search + '%')

end
go