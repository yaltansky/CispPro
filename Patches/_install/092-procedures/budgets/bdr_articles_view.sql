if object_id('bdr_articles_view') is not null
	drop proc bdr_articles_view
go
create proc bdr_articles_view
	@name varchar(50)
as
begin

	set nocount on;

	select * from bdr_articles
	where name like '%' + @name + '%'

end
GO
