if object_id('maxof') is not null drop function maxof
go
create function maxof(@v1 float, @v2 float, @v3 float)
returns float
as begin

	return 
		case
			when isnull(@v1,0) >= isnull(@v2,0) and isnull(@v1,0) >= isnull(@v3,0) then isnull(@v1,0)
			when isnull(@v2,0) >= isnull(@v1,0) and isnull(@v2,0) >= isnull(@v3,0) then isnull(@v2,0)
			when isnull(@v3,0) >= isnull(@v1,0) and isnull(@v3,0) >= isnull(@v2,0) then isnull(@v3,0)
			else isnull(@v1,0)
		end
end
GO
