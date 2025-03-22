if object_id('hashids') is not null drop function hashids
go
create function hashids(@search varchar(max))
returns @search_ids table (id int primary key)
as 
begin

	if dbo.hashid(@search) is not null
		insert into @search_ids select dbo.hashid(@search)

	else if charindex('#', @search) > 0
		insert into @search_ids select distinct item from dbo.str2rows(@search, '#') where try_parse(item as int) is not null

	return;
end
GO
