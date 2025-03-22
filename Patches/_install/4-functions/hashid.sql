if object_id('hashid') is not null drop function hashid
go
create function hashid(@search varchar(max))
returns int
as begin

	declare @result int

	if substring(@search	, 1, 1) = '#'
	begin
		set @result = try_parse(substring(@search, 2, 30) as int)
	end

	return @result
end
GO
