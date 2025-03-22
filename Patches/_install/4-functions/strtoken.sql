if object_id('strtoken') is not null drop function strtoken
GO
create function strtoken(@source varchar(8000), @separator char(1), @index int)
returns varchar(8000)
as
begin

	declare @items table(row_id int identity, item varchar(8000))
	insert into @items(item) 
	select item from dbo.str2rows(@source, @separator)

	declare @result varchar(8000) = (select item from @items where row_id = @index)
	return @result
end
go
