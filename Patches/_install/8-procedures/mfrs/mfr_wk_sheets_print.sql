-- dbcontext: CISP_SEZ | CISP_SEZ_TEST
if object_id('mfr_wk_sheets_print') is not null drop proc mfr_wk_sheets_print
go
create proc mfr_wk_sheets_print
	@folder_id int,
	@print_type varchar(32) = 'award'
as
begin
    set nocount on;

-- @objs
  declare @objs app_pkids
    insert into @objs select obj_id
    from objs_folders_details
    where folder_id = @folder_id
        and obj_type = 'MFW'

  if (@print_type = 'award') 
  begin
    -- tables
      create table #data_award (
        place varchar(255),
        mol_id int,
        full_name varchar(400),
        tab_number varchar(50),
        post_name varchar(150),
        fact_date datetime,
        wk_number varchar(50),
        wk_hours float,
        wk_shift varchar(20),
        ktu float,
        ktd float,
        k_inc float,
        salary_base decimal(18,2),
        salary_award decimal(18,2),
        salary decimal(18,2)
      )

    -- реестр данных
      insert into #data_award (place, mol_id, full_name, tab_number, post_name, fact_date, wk_number, wk_hours, wk_shift, ktu, ktd, k_inc, salary_base, salary_award, salary)
          select
              place = isnull(l.note, '') + ' (' + l.name + ')',
              r.mol_id,
              full_name = ltrim(rtrim(m.surname + ' ' + isnull(m.name1, '') + ' ' + isnull(m.name2, ''))),
              m.tab_number,
              post_name = p.name,
              fact_date = h.d_doc,
              wk_number = h.number,
              r.wk_hours,
              wk_shift = isnull(
                          replace(
                            replace(
                              replace(upper(r.wk_shift), 'С', 'C'),
                              'Р', 'P'
                            ), 'В', 'B'
                          ), '1'),
              r.ktu,
              ktd = isnull(r.ktd, 0.0),
              r.k_inc,
              r.salary_base,
              salary_award = cast(isnull(r.salary_award, 0.0) / (1-isnull(r.ktd, 0.0)) as decimal(19,2)),
              r.salary
          from
              mfr_wk_sheets h
                  join mfr_wk_sheets_salary r on (h.wk_sheet_id = r.wk_sheet_id)
                  join mols m on (r.mol_id = m.mol_id)
                  left join mols_posts p on (m.post_id = p.post_id)
                  left join mfr_places l on (h.place_id = l.place_id)
                  -- фильтр по документам
                  join @objs o on (o.id = h.wk_sheet_id)
          where
            r.salary_award > 0

      -- отчётный период
        declare @PeriodName varchar(50) = (
            select 
                'с ' + convert(varchar(10), min(t.fact_date), 104) + ' ' +
                'по ' + convert(varchar(10), max(t.fact_date), 104)
            from #data_award t)

      -- учтём ktd
        update t set t.salary_award = t.salary_award * (1 - k.ktd)
          from
            #data_award t
              join (
                select
                    mol_id,
                    ktd = case when (sum(isnull(ktd, 0.0)) > 0.5) then 0.5 else sum(isnull(ktd, 0.0)) end
                  from #data_award
                  group by mol_id
              ) k on (t.mol_id = k.mol_id)

      -- отчёт
        select
            PeriodName         = @PeriodName,
            PlaceName          = place,
            AwardType          = case code
                                   when '16' then 'Сдельно'
                                   when '18' then 'Сверхурочные'
                                   when '19' then 'Выходные дни'
                                 end,
            NPP                = row_number() over(partition by place,code order by full_name),
            TabName            = tab_number,
            PersonName         = full_name,
            BalanceAccountName = '20',
            CostAccountName    = 'Основное производство',
            PayType            = '2',
            Award              = salary_award
          from (
            select 
                place, mol_id, full_name, tab_number, post_name, code,
                fact_date = max(fact_date),
                salary_award = sum(salary_award)
            from (
                select
                    place,
                    mol_id,
                    full_name,
                    tab_number,
                    post_name,
                    code = case 
                                when
                                    (patindex('%[123]%', wk_shift) != 0) and
                                    (patindex('%[C]%', wk_shift) != 0) and
                                    (patindex('%[PB]%', wk_shift) = 0)
                                then '18' -- сверхурочные
                                else case when
                                    (patindex('%[123]%', wk_shift) != 0) and
                                    (patindex('%[PB]%', wk_shift) != 0) and
                                    (patindex('%[C]%', wk_shift) = 0)
                                    then '19' -- работа в выходные и праздничные дни
                                    else '16' -- сдельно
                                end
                            end,
                    fact_date,
                    salary_award
                from #data_award
                ) x
                group by 
                    place, mol_id, full_name, tab_number, post_name, code
          ) m
          order by
            place, code, full_name

      --
        exec drop_temp_table '#data_award'
  
  end -- @print_type = 'award'

end
GO
