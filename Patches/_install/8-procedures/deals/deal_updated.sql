if object_id('deal_updated') is not null drop procedure deal_updated
go
create proc deal_updated
	@mol_id int,
	@deal_id int
as
begin
	
	set nocount on;

    -- purge
        delete from deals_products where deal_id = @deal_id and product_id is null and name is null
        delete from deals_costs where deal_id = @deal_id and article_id not in (select article_id from bdr_articles)
        delete from deals_costs where deal_id = @deal_id 
            and (
                isnull(value_bdr,0) = 0
                or not exists(select 1 from deals_products where deal_id = @deal_id and row_id = deals_costs.deal_product_id)
                )

    -- check value_ccy
        if abs(
            (select sum(value_ccy) from deals where deal_id = @deal_id)
            -
            isnull((select sum(value_bds) from deals_products where deal_id = @deal_id),0)
            ) > 1.00
            raiserror('Сумма сделки не соответствует сумме спецификации сделки.', 16, 1)
        
    -- check program_id
        declare @program_id int = (select program_id from deals where deal_id = @deal_id)
        declare @parent_id int = (select top 1 parent_id from projects where project_id = @deal_id and parent_id is not null)

        if @program_id is not null
        begin
            if @parent_id is null exec deal_program_attach @mol_id = @mol_id, @deal_id = @deal_id, @program_id = @program_id
        end

        else if @parent_id is not null begin
            exec deal_program_detach @mol_id = @mol_id, @deal_id = @deal_id
        end

    -- build pay_conditions
        declare @prefixes table(task_name varchar(50), prefix varchar(10))
            insert into @prefixes(task_name, prefix) values
                ('Запуск', 'З'),
                ('Подписание спецификации', 'А'),
                ('Изготовление', 'И'),
                ('Уведомление о готовности', 'УГ'),
                ('Отгрузка', 'О'),
                ('Доставка', 'Д'),
                ('Пусконаладка', 'П'),
                ('Акт выполненых работ', 'АКТ')

        declare @pay_conditions varchar(max)

        update x
        set @pay_conditions = (
                select concat(
                    isnull(map.prefix, upper(substring(db.task_name, 1, 1))),
                    case when db.date_lag > 0 then '+' else '-' end,
                    db.date_lag,
                    case when db.date_lag is not null then 'д' end,
                    case when db.ratio > 0 then '*' end,
                    cast(db.ratio * 100 as int),
                    case when db.ratio > 0 then '%' end,
                    ';') [text()] 
                from deals_budgets db
                    left join @prefixes map on map.task_name = db.task_name
                where db.deal_id = x.deal_id
                    and db.type_id = 1
                    and db.ratio > 0	
                for xml path('')
                ),
            pay_conditions = 
                case
                    when len(@pay_conditions) > 1 then substring(substring(@pay_conditions, 1, len(@pay_conditions) - 1), 1, 50)
                end,
            update_date = getdate(),
            update_mol_id = @mol_id
        from deals x
        where x.deal_id = @deal_id

    -- access
        declare @deals app_pkids; insert into @deals select @deal_id
        exec deals_calc @deals = @deals
end
go
