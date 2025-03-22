if object_id('xml2json') is not null drop function xml2json
GO
create function [dbo].[xml2json] (@xml xml)
returns varchar(max)
AS
begin
	declare @includeHeader bit = 0
	declare @toLowerCase bit = 0
	declare @toAngular bit = 0

    declare @Head varchar(max) = '', @json varchar(max) = ''

    ;with 
		cteEAV as (
			select 
				RowNr = row_number() over (order by (select null))
				, Entity    = xRow.value('@*[1]','varchar(100)')
				, Attribute = xAtt.value('local-name(.)','varchar(100)')
				, Value     = xAtt.value('.','varchar(1000)') 
			from @xml.nodes('/row') As r(xRow) 
				cross apply r.xRow.nodes('./@*') As A(xAtt) 
		)
		, cteSum as (
			select 
				Records = count(distinct Entity)
				, Head = iif(
					@includeHeader = 0, 
						'[[getResults]]',
						concat('{"status":{"successful":"true", "timestamp":"',
							format(GetUTCDate(), 'yyyy-MM-dd hh:mm:ss '), 'GMT','", "rows":"',
							count(distinct Entity),'"},"results":[[getResults]]}'
							) 
						) 
			from cteEAV
		)
        , cteBld as (
			select *
                , NewRow = iif(Lag(Entity,1) over (partition by Entity order by (select null)) = Entity, '', ',{')
                , EndRow = iif(Lead(Entity,1) over (partition by Entity order by (select null)) = Entity, ',', '}')
				, JSON = 
					iif(@toAngular = 0,
						concat('"', iif(@toLowerCase = 1, lower(attribute), attribute), '":', '"', replace(Value, '"', ''), '"'),
						concat(iif(@toLowerCase = 1, lower(attribute), attribute), ':', '`', replace(Value, '"', ''), '`')
					)
            from cteEAV
            where nullif(value, '') is not null
		)
    select 
		@json = @json + NewRow + json + EndRow,
		@head = Head
	from cteBld, cteSum
	order by RowNr

    return replace(@head, '[getResults]', stuff(@json, 1, 1,''))
end
-- Parameter 1: (select * from ... for xml raw)
GO

-- set @toAngular to 1 (see above) and then run:

-- SELECT DBO.XML2JSON((
--     SELECT O_KEY, O_PARENT, O_NAME, O_TYPE, O_TYPE_PARAM, O_REQUIRED, O_READONLY, O_HINT, O_FLEX, O_CSS FROM OPTIONS
--     WHERE O_GROUP = 'PROJECT'
--     ORDER BY ID
--     FOR XML RAW
--     ))
